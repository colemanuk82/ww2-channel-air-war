class_name CloudField
extends Node3D
## Volumetric clouds (raymarched box proxies, shaders/cloud_volume.gdshader) in four types, laid out as
## weather-system formations that wrap around the camera (endless):
##   CUMULUS   fair-weather puffs in fields / cloud streets          (base ~450-700 m)
##   TOWER     towering cumulus / cumulonimbus with anvils            (storm cells)
##   STRATO    broad broken stratocumulus decks                       (overcast / rain)
##   CIRRUS    high thin wisps, all aligned with the wind
##   ALTO      mid-level altocumulus "mackerel sky" patches
##   LENS      altocumulus lenticularis: smooth lens / stacked plates, long axis across the wind
##   CASTLE    altocumulus castellanus: turrets rising off a flat mid-level base (instability)
##   CIRROCU   cirrocumulus: high rippled sheets of tiny cells
##   CONGESTUS tall cauliflower heaps, no anvil (between cumulus and towers)
##   STRATUS   low smooth grey sheets (overcast / rain)
## Layers (world-unit base heights, altitude m = y/2): low strato/stratus ~700-900, cumulus 950-2000 (several
## stacked sub-layers), altocumulus + altostratus 4500-7000, cirrus 9500-12500.
## `cover` (0..1, set by WeatherManager) decides which clouds exist: each cloud has a random rank and a
## per-type threshold, so clear skies = few cumulus + cirrus, overcast = decks, storm = towers + decks.
## Public: cover, mat (shared ShaderMaterial: cloud_color, shade_color, light_level, density_scale),
## blocks_los(p1, p2).

enum Kind { CUMULUS, TOWER, STRATO, CIRRUS, ALTO, LENS, CASTLE, CIRROCU, CONGESTUS, STRATUS }

@export var wrap_size: float = 100000.0
@export var field_count: int = 84

var cover: float = 0.3:
	set(v):
		cover = clampf(v, 0.0, 1.0)
		RenderingServer.global_shader_parameter_set("cloud_shadow", cover)   # drifting cloud shadows on the terrain
		_apply_cover()
var mat: ShaderMaterial
var _centers: PackedVector3Array   # cloud centres
var _radii: PackedVector3Array     # ellipsoid radii (rx, ry, rz) in world units
var _kinds: PackedInt32Array
var _ranks: PackedFloat32Array     # random 0..1 appearance rank
var _yaws: PackedFloat32Array
var _nodes: Array = []             # MeshInstance3D per cloud (same order as the arrays)
var _wind_yaw: float = 0.6
var _rainonly: PackedByteArray      # 1 = low ragged scud that only exists while it rains
var _flag_next: bool = false
var _shaft_mat: ShaderMaterial
var rain_level: float = 0.0         # 0..1, fed by WeatherManager
var rain_here: float = 0.0          # rain from a cloud directly overhead of the camera (0..1)
var _shaft_amount_set: float = -1.0


var _perf_off: bool = OS.get_cmdline_user_args().has("--no-clouds")


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1066
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 2.0, 2.0)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/cloud_volume.gdshader") as Shader
	# Transparent objects sort by distance; the huge sea plane under the camera would otherwise draw after
	# (on top of) every cloud below the horizon, leaving a hard cut. Higher priority = drawn after the water.
	mat.render_priority = 20
	set_detail(GameState.cloud_detail)
	var half: float = wrap_size * 0.5
	# formations
	for f in field_count:
		var fc := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var roll: float = rng.randf()
		if roll < 0.18:
			_cumulus_field(rng, fc)
		elif roll < 0.26:
			_strato_deck(rng, fc, 6, 7000.0)
		elif roll < 0.32:
			_strato_deck(rng, fc, 16, 13000.0)     # wide overcast sheet
		elif roll < 0.42:
			_cirrus_streaks(rng, fc)
		elif roll < 0.52:
			_alto_patch(rng, fc)
		elif roll < 0.64:
			_storm_cell(rng, fc)
		elif roll < 0.90:
			_massif(rng, fc, rng.randf() < 0.45)
		else:
			_front_line(rng, fc)
	# ragged scud under the rain clouds (only appears while it rains)
	for f in 26:
		_scud(rng, Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))
	# lone cumulus between the formations
	for i in 90:
		_add(rng, Kind.CUMULUS, Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)), rng.randf_range(0.6, 1.0), rng.randf() * TAU)
	# v7.23 cloud types: their own generator so the original sky above stays exactly where it was
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1940
	var new_n: int = 0 if OS.get_cmdline_user_args().has("--no-newclouds") else 34
	for f in new_n:
		var fc2 := Vector2(rng2.randf_range(-half, half), rng2.randf_range(-half, half))
		var r2: float = rng2.randf()
		if r2 < 0.18:
			_lens_group(rng2, fc2)
		elif r2 < 0.38:
			_castle_patch(rng2, fc2)
		elif r2 < 0.58:
			_cirrocu_sheet(rng2, fc2)
		elif r2 < 0.82:
			_congestus_group(rng2, fc2)
		else:
			_stratus_sheet(rng2, fc2)
	for i in (0 if new_n == 0 else 30):   # lone congestus heaps among the fair-weather cumulus
		_add(rng2, Kind.CONGESTUS, Vector2(rng2.randf_range(-half, half), rng2.randf_range(-half, half)), rng2.randf_range(0.7, 1.15), rng2.randf() * TAU)
	# nodes
	for i in _centers.size():
		var r: Vector3 = _radii[i]
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = r
		mi.rotation.y = _yaws[i]
		mi.set_instance_shader_parameter("seed", rng.randf() * 60.0)
		mi.set_instance_shader_parameter("ctype", float(_kinds[i]))
		mi.set_instance_shader_parameter("nfreq", 1.8 * clampf(sqrt(maxf(r.x, r.z) / 450.0), 1.0, 2.6))
		mi.position = _centers[i]
		add_child(mi)
		_nodes.append(mi)
		if _kinds[i] == Kind.TOWER or (_kinds[i] == Kind.STRATO and _centers[i].y < 1400.0 and _radii[i].x > 2200.0 and _ranks[i] < 0.5):
			_add_shaft(mi, _centers[i].y, r)
	_apply_cover()


## Open tube, UV.y = 1 at the cloud end (top) and 0 at the ground end, UV.x around the tube.
static func _shaft_mesh(height: float) -> ArrayMesh:
	var segs: int = 16
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var a: float = float(i) / float(segs) * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		verts.append(dir * 0.5 + Vector3(0, height * 0.5, 0))
		verts.append(dir * 0.62 - Vector3(0, height * 0.5, 0))
		uvs.append(Vector2(float(i) / float(segs), 1.0))
		uvs.append(Vector2(float(i) / float(segs), 0.0))
		norms.append(dir)
		norms.append(dir)
	for i in segs:
		var b: int = i * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A curtain of rain hanging under a rain cloud (child of the cloud, so it moves and hides with it).
func _add_shaft(cloud: MeshInstance3D, centre_y: float, r: Vector3) -> void:
	if _shaft_mat == null:
		_shaft_mat = ShaderMaterial.new()
		_shaft_mat.shader = load("res://shaders/rain_shaft.gdshader") as Shader
		_shaft_mat.render_priority = 21
	var base_local: float = -0.62                               # just under the cloud's underside, in unit-box space
	var drop: float = (centre_y - 40.0) / maxf(r.y, 1.0)        # down to roughly the ground, in unit-box space
	var sh := MeshInstance3D.new()
	sh.mesh = _shaft_mesh(drop)
	sh.material_override = _shaft_mat
	sh.position = Vector3(0, base_local - drop * 0.5, 0)
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.visible = false
	sh.add_to_group("rain_shaft")
	cloud.add_child(sh)


## Adds one cloud. size_k scales its radii; yaw rotates it about Y; base_override fixes its base height.
func _add(rng: RandomNumberGenerator, kind: int, xz: Vector2, size_k: float, yaw: float, base_override: float = -1.0, rank: float = -1.0) -> void:
	var r: Vector3
	var base: float
	match kind:
		Kind.CUMULUS:
			r = Vector3(rng.randf_range(380.0, 850.0), rng.randf_range(230.0, 430.0), rng.randf_range(320.0, 700.0))
			base = rng.randf_range(950.0, 1350.0)
		Kind.TOWER:
			r = Vector3(rng.randf_range(750.0, 1300.0), rng.randf_range(1200.0, 2100.0), rng.randf_range(650.0, 1150.0))
			base = rng.randf_range(850.0, 1100.0)
		Kind.STRATO:
			r = Vector3(rng.randf_range(1900.0, 3600.0), rng.randf_range(140.0, 260.0), rng.randf_range(1500.0, 2900.0))
			base = rng.randf_range(750.0, 1000.0)
		Kind.ALTO:
			r = Vector3(rng.randf_range(700.0, 1400.0), rng.randf_range(90.0, 170.0), rng.randf_range(600.0, 1200.0))
			base = rng.randf_range(4500.0, 6500.0)
		Kind.LENS:
			r = Vector3(rng.randf_range(1500.0, 2800.0), rng.randf_range(140.0, 280.0), rng.randf_range(650.0, 1200.0))
			base = rng.randf_range(3200.0, 5600.0)
		Kind.CASTLE:
			r = Vector3(rng.randf_range(900.0, 1600.0), rng.randf_range(300.0, 480.0), rng.randf_range(800.0, 1400.0))
			base = rng.randf_range(3400.0, 5200.0)
		Kind.CIRROCU:
			r = Vector3(rng.randf_range(2600.0, 5000.0), rng.randf_range(70.0, 120.0), rng.randf_range(1900.0, 3600.0))
			base = rng.randf_range(8200.0, 10500.0)
		Kind.CONGESTUS:
			r = Vector3(rng.randf_range(600.0, 1000.0), rng.randf_range(750.0, 1250.0), rng.randf_range(550.0, 950.0))
			base = rng.randf_range(900.0, 1250.0)
		Kind.STRATUS:
			r = Vector3(rng.randf_range(3200.0, 6000.0), rng.randf_range(90.0, 150.0), rng.randf_range(2600.0, 5000.0))
			base = rng.randf_range(520.0, 760.0)
		_:
			r = Vector3(rng.randf_range(3800.0, 7500.0), rng.randf_range(110.0, 190.0), rng.randf_range(520.0, 1100.0))
			base = rng.randf_range(9500.0, 12500.0)
	if base_override > 0.0:
		base = base_override
	r *= size_k
	_centers.append(Vector3(xz.x, base + r.y * 0.45, xz.y))
	_radii.append(r)
	_kinds.append(kind)
	_ranks.append(rank if rank >= 0.0 else rng.randf())
	_yaws.append(yaw)
	_rainonly.append(1 if _flag_next else 0)


## Fair-weather cumulus field: a loose elongated cluster, often drawn out into streets along the wind.
func _cumulus_field(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var n: int = rng.randi_range(10, 24)
	var along: float = rng.randf_range(7000.0, 16000.0)
	var across: float = along * rng.randf_range(0.25, 0.6)
	var dir := Vector2(cos(_wind_yaw), sin(_wind_yaw))
	var side := Vector2(-dir.y, dir.x)
	var street: bool = rng.randf() < 0.4
	# several stacked cumulus layers: low scruffy fair-weather, normal, and higher heaped cumulus
	var lroll: float = rng.randf()
	var field_base: float = rng.randf_range(650.0, 800.0) if lroll < 0.2 else (rng.randf_range(950.0, 1300.0) if lroll < 0.7 else rng.randf_range(1600.0, 2100.0))
	for i in n:
		var u: float = rng.randf_range(-1.0, 1.0)
		var v: float = rng.randf_range(-1.0, 1.0)
		if street:
			v = snappedf(v, 0.5) + rng.randf_range(-0.07, 0.07)   # parallel rows
		var p: Vector2 = fc + dir * u * along + side * v * across
		# bigger in the middle of the field, smaller wisps at the ragged edge
		var k: float = lerpf(1.25, 0.55, clampf(Vector2(u, v).length(), 0.0, 1.0)) * rng.randf_range(0.85, 1.15)
		_add(rng, Kind.CUMULUS, p, k, rng.randf() * TAU, field_base + rng.randf_range(-60.0, 60.0))
	if rng.randf() < 0.22:
		_add(rng, Kind.TOWER, fc + dir * rng.randf_range(-0.3, 0.3) * along, rng.randf_range(0.7, 1.0), rng.randf() * TAU)


## Broken stratocumulus deck: overlapping broad rolls.
func _strato_deck(rng: RandomNumberGenerator, fc: Vector2, count: int = 0, spread_max: float = 9000.0) -> void:
	var n: int = count if count > 0 else rng.randi_range(5, 10)
	var spread: float = rng.randf_range(spread_max * 0.6, spread_max)
	var deck_rank: float = rng.randf()
	# mostly a low stratus deck, sometimes a thin high altostratus sheet
	var high: bool = rng.randf() < 0.3
	var base: float = rng.randf_range(5200.0, 7000.0) if high else rng.randf_range(680.0, 980.0)
	for i in n:
		var p: Vector2 = fc + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread * (1.5 if high else 1.0)
		_add(rng, Kind.STRATO, p, rng.randf_range(0.8, 1.2) * (1.5 if high else 1.0), _wind_yaw + rng.randf_range(-0.3, 0.3), base + rng.randf_range(-40.0, 40.0), deck_rank if count > 8 else -1.0)


## High cirrus: parallel streaks aligned with the wind.
func _cirrus_streaks(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var n: int = rng.randi_range(5, 12)
	var along := Vector2(cos(_wind_yaw), sin(_wind_yaw))
	var side := Vector2(-along.y, along.x)
	var base: float = rng.randf_range(10000.0, 12000.0)
	for i in n:
		var p: Vector2 = fc + side * rng.randf_range(-9000.0, 9000.0) + along * rng.randf_range(-6000.0, 6000.0)
		_add(rng, Kind.CIRRUS, p, rng.randf_range(0.7, 1.3), -_wind_yaw + rng.randf_range(-0.12, 0.12), base + rng.randf_range(-400.0, 400.0))


## Big heaped cloud mass (cumulus congestus complex): a dome of overlapping clouds, huge in the middle,
## smaller towards the ragged edge, optionally with cumulonimbus towers in the core. The whole mass shares
## one appearance rank, so it appears or goes as a single formation.
func _massif(rng: RandomNumberGenerator, fc: Vector2, tall: bool) -> void:
	var core: float = rng.randf_range(3500.0, 7500.0)
	var n: int = rng.randi_range(18, 32)
	var base: float = rng.randf_range(850.0, 1250.0)
	var mass_rank: float = rng.randf_range(0.0, 0.8)
	for i in n:
		var a: float = rng.randf() * TAU
		var dist: float = core * sqrt(rng.randf())
		var h: float = 1.0 - dist / core                      # 1 at the centre, 0 at the edge
		var kind: int = Kind.TOWER if (tall and h > 0.5 and rng.randf() < 0.55) else Kind.CUMULUS
		var k: float = lerpf(0.9, 2.7, h) * rng.randf_range(0.85, 1.15)
		_add(rng, kind, fc + Vector2(cos(a), sin(a)) * dist, k, rng.randf() * TAU, base + h * rng.randf_range(0.0, 700.0), mass_rank)
	# a skirt of small cumulus around it
	for i in rng.randi_range(5, 10):
		var a2: float = rng.randf() * TAU
		_add(rng, Kind.CUMULUS, fc + Vector2(cos(a2), sin(a2)) * core * rng.randf_range(1.0, 1.6), rng.randf_range(0.5, 0.9), rng.randf() * TAU, base + rng.randf_range(-60.0, 60.0), mass_rank)


## Low ragged scud (fractocumulus) drifting under rain clouds: small, dark, torn.
func _scud(rng: RandomNumberGenerator, fc: Vector2) -> void:
	_flag_next = true
	var n: int = rng.randi_range(9, 18)
	for i in n:
		var p: Vector2 = fc + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 4200.0
		_add(rng, Kind.CUMULUS, p, rng.randf_range(0.28, 0.62), rng.randf() * TAU, rng.randf_range(380.0, 700.0), rng.randf())
	_flag_next = false


## Frontal line: a long wall of tightly packed heaped cumulus and towering cells at right angles to the wind.
func _front_line(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var side := Vector2(-sin(_wind_yaw), cos(_wind_yaw))
	var along := Vector2(cos(_wind_yaw), sin(_wind_yaw))
	var n: int = rng.randi_range(14, 24)
	var spacing: float = rng.randf_range(1800.0, 2600.0)
	var base: float = rng.randf_range(850.0, 1150.0)
	var front_rank: float = rng.randf_range(0.0, 0.7)
	for i in n:
		var u: float = (float(i) - float(n) * 0.5) * spacing
		var p: Vector2 = fc + side * u + along * rng.randf_range(-900.0, 900.0) + along * sin(u * 0.00007) * 2500.0
		var tower: bool = rng.randf() < 0.45
		_add(rng, Kind.TOWER if tower else Kind.CUMULUS, p, rng.randf_range(1.1, 1.8) if not tower else rng.randf_range(0.9, 1.4), rng.randf() * TAU, base + rng.randf_range(-50.0, 50.0), front_rank)


## Altocumulus: rows of small flat cloudlets at mid level, loosely aligned with the wind.
func _alto_patch(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var n: int = rng.randi_range(8, 18)
	var along := Vector2(cos(_wind_yaw), sin(_wind_yaw))
	var side := Vector2(-along.y, along.x)
	var base: float = rng.randf_range(4600.0, 6400.0)
	for i in n:
		var p: Vector2 = fc + along * rng.randf_range(-9000.0, 9000.0) + side * snappedf(rng.randf_range(-7000.0, 7000.0), 2300.0) + side * rng.randf_range(-400.0, 400.0)
		_add(rng, Kind.ALTO, p, rng.randf_range(0.7, 1.3), rng.randf() * TAU, base + rng.randf_range(-120.0, 120.0))


## Storm cell: one to three big cumulonimbus ringed by cumulus and a skirt of strato.
func _storm_cell(rng: RandomNumberGenerator, fc: Vector2) -> void:
	for i in rng.randi_range(1, 3):
		_add(rng, Kind.TOWER, fc + Vector2(rng.randf_range(-2500, 2500), rng.randf_range(-2500, 2500)), rng.randf_range(0.85, 1.3), rng.randf() * TAU)
	for i in rng.randi_range(5, 9):
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(2500.0, 6500.0)
		_add(rng, Kind.CUMULUS, fc + Vector2(cos(a), sin(a)) * r, rng.randf_range(0.6, 1.1), rng.randf() * TAU, rng.randf_range(900.0, 1100.0))
	for i in rng.randi_range(2, 4):
		_add(rng, Kind.STRATO, fc + Vector2(rng.randf_range(-4000, 4000), rng.randf_range(-4000, 4000)), rng.randf_range(0.8, 1.1), _wind_yaw, rng.randf_range(760.0, 900.0))


## Lenticular group: one to four smooth lenses lined up across the wind (a standing wave), sometimes stacked.
func _lens_group(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var across := Vector2(-sin(_wind_yaw), cos(_wind_yaw))
	var along := Vector2(cos(_wind_yaw), sin(_wind_yaw))
	var rank: float = rng.randf() * 0.8
	var base: float = rng.randf_range(3200.0, 5400.0)
	for i in rng.randi_range(1, 4):
		var p: Vector2 = fc + across * rng.randf_range(-5000.0, 5000.0) + along * float(i) * rng.randf_range(2500.0, 4000.0)
		# long axis (local x) across the wind
		_add(rng, Kind.LENS, p, rng.randf_range(0.75, 1.25), -atan2(across.y, across.x) + rng.randf_range(-0.15, 0.15), base + rng.randf_range(-250.0, 250.0), rank)


## Castellanus: a band of turreted cloudlets at mid level.
func _castle_patch(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var along := Vector2(cos(_wind_yaw), sin(_wind_yaw))
	var side := Vector2(-along.y, along.x)
	var base: float = rng.randf_range(3500.0, 5000.0)
	for i in rng.randi_range(4, 10):
		var p: Vector2 = fc + along * rng.randf_range(-7000.0, 7000.0) + side * rng.randf_range(-2500.0, 2500.0)
		_add(rng, Kind.CASTLE, p, rng.randf_range(0.7, 1.3), rng.randf() * TAU, base + rng.randf_range(-150.0, 150.0))


## Cirrocumulus: two to five high rippled sheets.
func _cirrocu_sheet(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var base: float = rng.randf_range(8400.0, 10300.0)
	for i in rng.randi_range(2, 5):
		var p: Vector2 = fc + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 7000.0
		_add(rng, Kind.CIRROCU, p, rng.randf_range(0.7, 1.3), _wind_yaw + rng.randf_range(-0.4, 0.4), base + rng.randf_range(-200.0, 200.0))


## A cluster of congestus heaps with small cumulus at their feet.
func _congestus_group(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var rank: float = rng.randf_range(0.0, 0.9)
	var base: float = rng.randf_range(900.0, 1200.0)
	for i in rng.randi_range(3, 7):
		var p: Vector2 = fc + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 4500.0
		_add(rng, Kind.CONGESTUS, p, rng.randf_range(0.8, 1.3), rng.randf() * TAU, base + rng.randf_range(-40.0, 40.0), rank)
	for i in rng.randi_range(4, 9):
		var p2: Vector2 = fc + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 6500.0
		_add(rng, Kind.CUMULUS, p2, rng.randf_range(0.5, 0.9), rng.randf() * TAU, base + rng.randf_range(-40.0, 40.0), rank)


## Low stratus: one to three smooth grey sheets, only under heavy cover.
func _stratus_sheet(rng: RandomNumberGenerator, fc: Vector2) -> void:
	var rank: float = rng.randf()
	var base: float = rng.randf_range(540.0, 760.0)
	for i in rng.randi_range(1, 3):
		var p: Vector2 = fc + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 6000.0
		_add(rng, Kind.STRATUS, p, rng.randf_range(0.8, 1.2), _wind_yaw + rng.randf_range(-0.3, 0.3), base + rng.randf_range(-30.0, 30.0), rank)


## Which clouds exist for the current cover value (see class doc).
func _kind_visible(kind: int, rank: float, c_override: float = -1.0) -> bool:
	var c: float = cover if c_override < 0.0 else c_override
	match kind:
		Kind.CUMULUS:
			return rank < clampf(c * 1.15 + 0.06, 0.0, 1.0) * (1.0 if c < 0.7 else 0.55)   # thins out again under overcast
		Kind.TOWER:
			return rank < clampf((c - 0.45) * 1.6, 0.0, 1.0) * 0.9
		Kind.STRATO:
			return rank < clampf((c - 0.3) * 1.5, 0.0, 1.0)
		Kind.CONGESTUS:
			return rank < clampf((c - 0.25) * 1.5, 0.0, 1.0) * (0.9 if c < 0.8 else 0.5)
		Kind.STRATUS:
			return rank < clampf((c - 0.6) * 2.2, 0.0, 1.0)
		Kind.CASTLE:
			return rank < clampf((c - 0.2) * 1.3, 0.0, 1.0) * 0.8
		Kind.LENS:
			return rank < 0.3 + 0.2 * c
		Kind.CIRROCU:
			return rank < 0.28 + 0.35 * c
	if kind == Kind.ALTO:
		return rank < 0.30 + 0.45 * c
	return rank < 0.35 + 0.4 * c


func _apply_cover() -> void:
	if WeatherManager.front_active:
		return                # per-cloud cover from the front (see _front_visibility)
	for i in _nodes.size():
		if _rainonly[i] == 1:
			(_nodes[i] as Node3D).visible = _ranks[i] < rain_level * 1.1 and rain_level > 0.2
		else:
			(_nodes[i] as Node3D).visible = _kind_visible(_kinds[i], _ranks[i])


var _front_was_active: bool = false


func _front_visibility(cp: Vector3) -> void:
	var active: bool = WeatherManager.front_active
	if not active:
		if _front_was_active:
			_front_was_active = false
			_apply_cover()
		return
	_front_was_active = true
	var half: float = wrap_size * 0.5
	var drift: Vector2 = WeatherManager.cloud_drift
	for i in _nodes.size():
		if _rainonly[i] == 1:
			continue
		var c: Vector3 = _centers[i] + Vector3(drift.x, 0.0, drift.y)
		var wp := Vector3(cp.x + fposmod(c.x - cp.x + half, wrap_size) - half, c.y, cp.z + fposmod(c.z - cp.z + half, wrap_size) - half)
		var cv: float = WeatherManager.cover_at(wp)
		(_nodes[i] as Node3D).visible = _kind_visible(_kinds[i], _ranks[i], cv)     # (cv < 0: front not placed yet -> global cover)


## Called every frame by WeatherManager: low scud and the rain curtains follow the rain level.
func set_rain_level(v: float) -> void:
	if absf(v - _shaft_amount_set) < 0.03:
		return
	_shaft_amount_set = v
	var was_on: bool = rain_level > 0.2
	rain_level = v
	if _shaft_mat:
		_shaft_mat.set_shader_parameter("amount", clampf(v * 1.2, 0.0, 1.0))
	for s in get_tree().get_nodes_in_group("rain_shaft"):
		(s as Node3D).visible = v > 0.18
	if was_on != (v > 0.2) or v > 0.2:
		_apply_cover()


## Rain falling on this point from a rain cloud overhead (towering cells at full strength, low deck at ~60%).
## Result in rain_here (0..1). Only meaningful while the clouds themselves are visible.
func sample_rain(p: Vector3) -> void:
	var best: float = 0.0
	var half: float = wrap_size * 0.5
	var dr: Vector2 = WeatherManager.cloud_drift
	for i in _centers.size():
		var k: int = _kinds[i]
		if not (k in [Kind.TOWER, Kind.STRATO, Kind.CONGESTUS, Kind.STRATUS]) or not (_nodes[i] as Node3D).visible:
			continue
		var c: Vector3 = _centers[i] + Vector3(dr.x, 0.0, dr.y)
		if p.y > c.y:
			continue      # above the cloud's heart: not under its rain
		var wx: float = p.x + fposmod(c.x - p.x + half, wrap_size) - half
		var wz: float = p.z + fposmod(c.z - p.z + half, wrap_size) - half
		var rh: float = (_radii[i].x + _radii[i].z) * 0.5 * 0.55
		var d: float = Vector2(p.x - wx, p.z - wz).length() / rh
		if d < 1.0:
			var w: float = (1.0 - d * d) * (1.0 if k == Kind.TOWER else (0.6 if k == Kind.STRATO else (0.5 if k == Kind.CONGESTUS else 0.35)))
			best = maxf(best, w)
	rain_here = clampf(best * 1.4, 0.0, 1.0)


var _front_vis_t: float = 0.0


## Volumetric cloud cost (settings "Cloud detail"): 0 low, 1 medium, 2 high.
func set_detail(level: int) -> void:
	if mat == null:
		return
	var sk: Array = [1.8, 1.3, 1.0]
	var ms: Array = [30, 44, 60]
	var le: Array = [3, 2, 2]
	var l: int = clampi(level, 0, 2)
	mat.set_shader_parameter("step_k", sk[l])
	mat.set_shader_parameter("max_steps", ms[l])
	mat.set_shader_parameter("light_every", le[l])


var _rr: int = 0


func _process(delta: float) -> void:
	if _perf_off:
		visible = false
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or _nodes.is_empty():
		return
	# a moving front: each cloud shows by the cover at its own position, so the front's wall of cloud is visible
	_front_vis_t -= delta
	if _front_vis_t <= 0.0:
		_front_vis_t = 1.0
		_front_visibility(cam.global_position)
	var cp: Vector3 = cam.global_position
	var half: float = wrap_size * 0.5
	var drift: Vector2 = WeatherManager.cloud_drift     # clouds move with the wind
	# a quarter of the clouds per frame: a cloud only jumps when it wraps at the far edge of the field (faded out
	# there), and the wind drift is slow, so 15 Hz per cloud is plenty
	_rr = (_rr + 1) % 4
	for i in range(_rr, _nodes.size(), 4):
		var n: Node3D = _nodes[i]
		if not n.visible:
			continue
		var c: Vector3 = _centers[i] + Vector3(drift.x, 0.0, drift.y)
		n.global_position = Vector3(
			cp.x + fposmod(c.x - cp.x + half, wrap_size) - half,
			c.y,
			cp.z + fposmod(c.z - cp.z + half, wrap_size) - half)
	mat.set_shader_parameter("sun_dir", TimeOfDay.sun_dir)


## True when the sight line p1 -> p2 passes through a cloud (ellipsoid test; cirrus is too thin to block).
## The field wraps around the camera, so each cloud is wrapped next to the line first.
func blocks_los(p1: Vector3, p2: Vector3) -> bool:
	if _centers.is_empty():
		return false
	var d: Vector3 = p2 - p1
	if d.length_squared() < 1.0:
		return false
	var half: float = wrap_size * 0.5
	var mid: Vector3 = (p1 + p2) * 0.5
	for i in _centers.size():
		if _kinds[i] == Kind.CIRRUS or _kinds[i] == Kind.CIRROCU or not (_nodes[i] as Node3D).visible:
			continue
		var c: Vector3 = _centers[i] + Vector3(WeatherManager.cloud_drift.x, 0.0, WeatherManager.cloud_drift.y)
		var wx: float = mid.x + fposmod(c.x - mid.x + half, wrap_size) - half
		var wz: float = mid.z + fposmod(c.z - mid.z + half, wrap_size) - half
		var r: Vector3 = _radii[i]
		var rh: float = (r.x + r.z) * 0.5 * 0.7
		var ry: float = r.y * 0.7
		# scale into unit-sphere space and test the segment against it
		var a := Vector3((p1.x - wx) / rh, (p1.y - c.y) / ry, (p1.z - wz) / rh)
		var dd := Vector3(d.x / rh, d.y / ry, d.z / rh)
		var t: float = clampf(-a.dot(dd) / dd.length_squared(), 0.0, 1.0)
		if (a + dd * t).length_squared() < 1.0:
			return true
	return false


## How deep inside cloud a point is: 0 outside .. 1 at the heart of one (visible clouds, cirrus ignored).
func density_at(p: Vector3) -> float:
	var best: float = 0.0
	var half: float = wrap_size * 0.5
	for i in _centers.size():
		if _kinds[i] == Kind.CIRRUS or _kinds[i] == Kind.CIRROCU or not (_nodes[i] as Node3D).visible:
			continue
		var c: Vector3 = _centers[i] + Vector3(WeatherManager.cloud_drift.x, 0.0, WeatherManager.cloud_drift.y)
		var r: Vector3 = _radii[i]
		var dy: float = (p.y - c.y) / (r.y * 0.75)
		if absf(dy) >= 1.0:
			continue
		var wx: float = p.x + fposmod(c.x - p.x + half, wrap_size) - half
		var wz: float = p.z + fposmod(c.z - p.z + half, wrap_size) - half
		var rh: float = (r.x + r.z) * 0.5 * 0.75
		var dx: float = (p.x - wx) / rh
		var dz: float = (p.z - wz) / rh
		var q: float = dx * dx + dy * dy + dz * dz
		if q < 1.0:
			best = maxf(best, 1.0 - q)
	return best


## Debug: world position of the nth visible cloud of a kind (-1 if none).
func debug_cloud_pos(kind: int, nth: int) -> Vector3:
	if kind == 99:   # the largest visible non-cirrus cloud
		var best: int = -1
		var best_v: float = 0.0
		for i in _centers.size():
			if _kinds[i] in [Kind.CIRRUS, Kind.STRATO, Kind.CIRROCU, Kind.STRATUS] or not (_nodes[i] as Node3D).visible:
				continue
			var v: float = _radii[i].x * _radii[i].y * _radii[i].z
			if v > best_v:
				best_v = v
				best = i
		return _centers[best] if best >= 0 else Vector3(0, -1, 0)
	var k: int = 0
	for i in _centers.size():
		if _kinds[i] == kind and (_nodes[i] as Node3D).visible:
			if k == nth:
				return _centers[i]
			k += 1
	# none showing yet (cover still blending in): force the nth of that kind on, debug views only
	k = 0
	for i in _centers.size():
		if _kinds[i] == kind:
			if k == nth:
				_ranks[i] = 0.0
				(_nodes[i] as Node3D).visible = true
				return _centers[i]
			k += 1
	return Vector3(0, -1, 0)
