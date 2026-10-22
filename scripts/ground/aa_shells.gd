class_name AAShells
extends Node3D
## Pooled anti-aircraft ammunition for all AAGuns: visible tracers (one MultiMesh) and invisible fused flak
## shells that burst near the aimed point. Damages enemy "aircraft" group members via take_damage().
## Singleton: AAShells.get_instance().

const MAX_TRACERS: int = 160

static var _inst: AAShells = null

var _shells: Array = []     # Dictionary: kind(0 tracer,1 flak) pos vel life fuse dmg radius team
var _mmi: MultiMeshInstance3D
var _targets: Array = []
var _target_t: float = 0.0


static func get_instance() -> AAShells:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var t: SceneTree = GroundKit.tree()
	if t == null:
		return null
	_inst = AAShells.new()
	_inst.name = "AAShells"
	var parent: Node = t.current_scene if t.current_scene else t.root
	parent.add_child(_inst)
	return _inst


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 4.0)
	mm.mesh = bm
	mm.instance_count = MAX_TRACERS
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = GroundKit.glow_mat(Color(1.0, 0.72, 0.2), 1.0)
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 5000.0
	add_child(_mmi)
	top_level = true


func fire_tracer(from: Vector3, vel: Vector3, dmg: float, team: String, life: float = 2.2) -> void:
	_shells.append({"k": 0, "p": from, "v": vel, "l": life, "f": 0.0, "d": dmg, "r": 0.0, "t": team})


func fire_flak(from: Vector3, vel: Vector3, fuse: float, dmg: float, radius: float, team: String) -> void:
	_shells.append({"k": 1, "p": from, "v": vel, "l": 0.0, "f": fuse, "d": dmg, "r": radius, "t": team})


func _refresh_targets() -> void:
	_targets.clear()
	var t: SceneTree = get_tree()
	for n in t.get_nodes_in_group("aircraft"):
		if GroundKit.aircraft_alive(n):
			_targets.append(n)


func _physics_process(delta: float) -> void:
	_target_t -= delta
	if _target_t <= 0.0:
		_target_t = 0.1
		_refresh_targets()
	var mm: MultiMesh = _mmi.multimesh
	var vis: int = 0
	var dmul: float = 0.7 + 0.3 * GroundKit.difficulty()
	var i: int = _shells.size() - 1
	while i >= 0:
		var sh: Dictionary = _shells[i]
		var p0: Vector3 = sh["p"]
		var v: Vector3 = sh["v"]
		var p1: Vector3 = p0 + v * delta
		sh["p"] = p1
		var remove: bool = false
		var team: String = sh["t"]
		if sh["k"] == 0:
			sh["l"] = float(sh["l"]) - delta
			for a in _targets:
				if not is_instance_valid(a) or str(a.get("team")) == team or str(a.get("team")) == "Neutral":
					continue
				var rad: float = (float(a.get("hit_radius")) if "hit_radius" in a else 6.0) + 0.8
				var c: Vector3 = (a as Node3D).global_position
				if _seg_dist(p0, p1, c) < rad:
					a.call("take_damage", float(sh["d"]) * dmul, null)
					remove = true
					break
			if sh["l"] <= 0.0 or p1.y < GroundKit.ground_y(p1.x, p1.z):
				remove = true
			elif vis < MAX_TRACERS:
				var b: Basis = Basis.looking_at(v.normalized(), Vector3.UP)
				mm.set_instance_transform(vis, Transform3D(b, p1))
				vis += 1
		else:
			sh["f"] = float(sh["f"]) - delta
			var burst: bool = sh["f"] <= 0.0
			if not burst:
				for a in _targets:
					if is_instance_valid(a) and str(a.get("team")) != team and (a as Node3D).global_position.distance_to(p1) < float(sh["r"]) * 0.35:
						burst = true
						break
			if burst:
				_burst(p1, sh, dmul)
				remove = true
		if remove:
			_shells[i] = _shells[_shells.size() - 1]
			_shells.pop_back()
		i -= 1
	mm.visible_instance_count = vis


func _burst(pos: Vector3, sh: Dictionary, dmul: float) -> void:
	GroundKit.flak_burst(pos, 1.0)
	var team: String = sh["t"]
	var r: float = sh["r"]
	for a in _targets:
		if not is_instance_valid(a) or str(a.get("team")) == team or str(a.get("team")) == "Neutral":
			continue
		var d: float = (a as Node3D).global_position.distance_to(pos)
		if d < r:
			a.call("take_damage", float(sh["d"]) * dmul * (1.0 - d / r), null)


static func _seg_dist(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab: Vector3 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.0001:
		return a.distance_to(c)
	var t: float = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(c)
