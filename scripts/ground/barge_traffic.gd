class_name BargeTraffic
extends Node3D
## Working barges on the canals and the big rivers near the player (C1): Dutch and Belgian peniches and Rhine barge
## trains (a tug towing three or four lighters) on the river lines, single barges on the canals, all sliding along the
## real polylines at walking pace. At most MAX barges at once, recycled as the player moves (nearest waterways first),
## each one MultiMesh-free: a single merged mesh per barge type, so a dozen barges cost about a dozen draw calls.
##
## Sources: Wikipedia - Peniche (barge); Rhine barge; the Rhine, Waal, Scheldt, Meuse and the Belgian / Dutch canal
## network carried most of the Low Countries' freight in the 1940s (and were Typhoon and Mustang targets in 1944-45).

const MAX := 12
const RADIUS := 9000.0
const SPEED := 2.4               # m/s, a loaded barge's pace
const LON_MIN_CONTINENT := 1.9   # barges on the continental waterways (the British canals carry narrowboats)

var _barges: Array = []          # {"node": Node3D, "pts": PackedVector2Array, "cum": PackedFloat32Array, "len": float, "s": float, "dir": float}
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1944
	name = "BargeTraffic"


func _process(delta: float) -> void:
	_timer -= delta
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	if _timer <= 0.0:
		_timer = 4.0
		_refresh(cp)
	for b in _barges:
		var bd: Dictionary = b
		var node: Node3D = bd["node"]
		if not is_instance_valid(node):
			continue
		var s: float = float(bd["s"]) + SPEED * delta * float(bd["dir"])
		var L: float = float(bd["len"])
		if s <= 0.0 or s >= L:      # end of the waterway: turn round rather than jump to the other end
			bd["dir"] = -float(bd["dir"])
			s = clampf(s, 0.0, L)
		bd["s"] = s
		var cum: PackedFloat32Array = bd["cum"]
		var pts: PackedVector2Array = bd["pts"]
		var i: int = clampi(cum.bsearch(s) - 1, 0, cum.size() - 2)
		var seg: float = maxf(cum[i + 1] - cum[i], 0.0001)
		var p: Vector2 = pts[i].lerp(pts[i + 1], clampf((s - cum[i]) / seg, 0.0, 1.0))
		var t: Vector2 = (pts[i + 1] - pts[i]).normalized() * float(bd["dir"])
		if t == Vector2.ZERO:
			continue
		node.global_position = Vector3(p.x, GroundKit.ground_y(p.x, p.y) + 0.3, p.y)
		node.rotation.y = atan2(-t.x, -t.y)


## Keep up to MAX barges on the waterways within RADIUS of the camera; drop the ones left behind.
func _refresh(cp: Vector3) -> void:
	var c2 := Vector2(cp.x, cp.z)
	for i in range(_barges.size() - 1, -1, -1):
		var bd: Dictionary = _barges[i]
		var n: Node3D = bd["node"]
		if not is_instance_valid(n) or Vector2(n.global_position.x, n.global_position.z).distance_to(c2) > RADIUS * 1.3:
			if is_instance_valid(n):
				n.queue_free()
			_barges.remove_at(i)
	if _barges.size() >= MAX:
		return
	var ll: Vector2 = WorldCoords.world_to_latlon(cp)
	if ll.y < LON_MIN_CONTINENT:
		return
	var cands: Array = []
	for i in CanalKit.canals.size():
		var cn: Dictionary = CanalKit.canals[i]
		if CanalKit._poly_near(cn["pts"], c2, RADIUS):
			cands.append([cn, false])
	for ln in RiverMesh.lines:
		var rd: Dictionary = ln
		if float(rd.get("len", 0.0)) > 20000.0 and CanalKit._poly_near(rd["pts"], c2, RADIUS):
			cands.append([rd, true])
	if cands.is_empty():
		return
	var tries: int = 0
	while _barges.size() < MAX and tries < 24:
		tries += 1
		var pick: Array = cands[_rng.randi() % cands.size()]
		var wd: Dictionary = pick[0]
		var river: bool = pick[1]
		var L: float = float(wd["len"])
		if L < 400.0:
			continue
		var s0: float = _rng.randf() * L
		var p0: Vector2 = CanalKit._sample(wd["pts"], wd["cum"], s0)
		if p0.distance_to(c2) > RADIUS or p0.distance_to(c2) < 600.0:
			continue
		var node := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = barge_train_mesh() if river and _rng.randf() < 0.6 else peniche_mesh()
		mi.visibility_range_end = 4500.0
		node.add_child(mi)
		add_child(node)
		_barges.append({"node": node, "pts": wd["pts"], "cum": wd["cum"], "len": L, "s": s0, "dir": 1.0 if _rng.randf() < 0.5 else -1.0, "river": river})


# ------------------------------------------------------------------ meshes (bow towards -Z, waterline y = 0)
## Peniche: the standard 38.5 x 5 m Freycinet barge, black hull, cargo hatches, wheelhouse and family cabin aft.
static func peniche_mesh() -> ArrayMesh:
	if Scatter._meshes.has("peniche"):
		return Scatter._meshes["peniche"]
	var hull := Color(0.12, 0.12, 0.12)
	var hatch := Color(0.30, 0.26, 0.18)
	var cabin := Color(0.62, 0.58, 0.48)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(5.0, 2.2, 38.5), Vector3(0, 0.4, 0), hull))
	parts.append(GroundKit.box_part(Vector3(4.2, 0.5, 28.0), Vector3(0, 1.6, -3.0), hatch))
	parts.append(GroundKit.box_part(Vector3(4.4, 2.0, 5.0), Vector3(0, 2.4, 16.0), cabin))
	parts.append(GroundKit.box_part(Vector3(2.4, 1.6, 2.2), Vector3(0, 4.1, 14.8), cabin.darkened(0.1)))
	parts.append(GroundKit.box_part(Vector3(0.1, 1.2, 1.6), Vector3(0, 2.8, -15.0), Color(0.75, 0.2, 0.15), Vector3.ZERO, false))   # bow flag / mast
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes["peniche"] = m
	return m


## Rhine barge train: a tug towing three laden lighters on a tow line.
static func barge_train_mesh() -> ArrayMesh:
	if Scatter._meshes.has("rhine_train"):
		return Scatter._meshes["rhine_train"]
	var hull := Color(0.14, 0.14, 0.15)
	var cargo := Color(0.22, 0.20, 0.18)
	var tug := Color(0.58, 0.20, 0.16)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(6.0, 2.6, 26.0), Vector3(0, 0.5, 0), hull))
	parts.append(GroundKit.box_part(Vector3(4.0, 2.4, 8.0), Vector3(0, 2.8, 3.0), tug))
	parts.append(GroundKit.cyl_part(0.6, 0.7, 4.0, Vector3(0, 5.0, 1.0), Color(0.1, 0.1, 0.1), Vector3.ZERO, 8))
	for i in 3:
		var z: float = 50.0 + float(i) * 82.0
		parts.append(GroundKit.box_part(Vector3(9.0, 2.4, 70.0), Vector3(0, 0.4, z), hull))
		parts.append(GroundKit.box_part(Vector3(7.6, 0.6, 58.0), Vector3(0, 1.8, z - 2.0), cargo))
		parts.append(GroundKit.box_part(Vector3(5.0, 1.8, 4.0), Vector3(0, 2.5, z + 31.0), Color(0.58, 0.55, 0.47)))
		parts.append(GroundKit.box_part(Vector3(0.1, 0.1, 12.0), Vector3(0, 1.5, z - 41.0), Color(0.1, 0.1, 0.1), Vector3.ZERO, false))   # tow line
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes["rhine_train"] = m
	return m
