class_name AirfieldProp
extends GroundTarget
## Destructible airfield scenery: a small cluster of identical props (parked aircraft, blister hangars, Nissen huts,
## trucks, tents, bomb dumps). One damageable node per cluster; when it dies the cluster is replaced by burnt wrecks.
## Create with AirfieldProp.create(kind, team, mesh, world_transforms).

const CONFIG := {
	"parked": {"hp": 45.0, "pts": 60, "mult": 0.6, "expl": 1.3, "pad": 5.0},
	"blister": {"hp": 90.0, "pts": 70, "mult": 0.4, "expl": 1.3, "pad": 6.0},
	"hut": {"hp": 70.0, "pts": 40, "mult": 0.5, "expl": 1.0, "pad": 5.0},
	"tent": {"hp": 35.0, "pts": 30, "mult": 0.8, "expl": 0.9, "pad": 4.0},
	"truck": {"hp": 30.0, "pts": 40, "mult": 0.9, "expl": 1.1, "pad": 3.0},
	"ammo": {"hp": 80.0, "pts": 120, "mult": 0.3, "expl": 3.4, "pad": 6.0},
	"tank": {"hp": 90.0, "pts": 120, "mult": 0.35, "expl": 1.5, "pad": 3.5},
	"gun": {"hp": 40.0, "pts": 60, "mult": 0.7, "expl": 1.0, "pad": 3.0},
}

var pkind: String = "hut"
var _mesh: Mesh
var _xf: Array = []          # Transform3D relative to this node
var _wreck_size: Vector3 = Vector3(4.0, 0.6, 4.0)


static func create(p_kind: String, p_team: String, p_mesh: Mesh, world_xforms: Array) -> AirfieldProp:
	var g := AirfieldProp.new()
	var cfg: Dictionary = CONFIG.get(p_kind, CONFIG["hut"])
	g.pkind = p_kind
	g.kind = "prop_" + p_kind
	g.team = p_team
	g.max_health = cfg["hp"]
	g.points = cfg["pts"]
	g.small_mult = cfg["mult"]
	g.explosion_size = cfg["expl"]
	g.smoke_scale = clampf(float(cfg["expl"]) * 0.55, 0.7, 2.0)
	g.smoke_height = 2.0
	g.display_name = p_kind.capitalize()
	g._mesh = p_mesh
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for t in world_xforms:
		lo = lo.min((t as Transform3D).origin)
		hi = hi.max((t as Transform3D).origin)
	var c: Vector3 = (lo + hi) * 0.5 if not world_xforms.is_empty() else Vector3.ZERO
	g.position = c
	for t2 in world_xforms:
		var tt: Transform3D = t2
		tt.origin -= c
		g._xf.append(tt)
	g.hit_radius = maxf((hi - lo).x, (hi - lo).z) * 0.5 + float(cfg["pad"])
	if p_mesh != null:
		var bb: AABB = p_mesh.get_aabb()
		g._wreck_size = Vector3(maxf(bb.size.x, 2.0), 0.5, maxf(bb.size.z, 2.0)) * 0.8
	return g


func _post_ready() -> void:
	add_to_group("airfield_prop")
	if pkind == "parked":
		var tm := Timer.new()
		tm.one_shot = true
		tm.wait_time = randf_range(6.0, 45.0)
		tm.timeout.connect(_engine_start_tick.bind(tm))
		add_child(tm)
		tm.start()


## Now and then a parked fighter near the player coughs out exhaust smoke as its engine is started.
func _engine_start_tick(tm: Timer) -> void:
	tm.wait_time = randf_range(25.0, 70.0)
	tm.start()
	if is_dead or _xf.is_empty() or _mesh == null:
		return
	var pl: Node3D = GroundKit.player_node() as Node3D
	if pl == null or pl.global_position.distance_to(global_position) > 1500.0:
		return
	var t: Transform3D = _xf[randi() % _xf.size()]
	var bb: AABB = _mesh.get_aabb()
	var nose: Vector3 = global_position + t.origin + t.basis * Vector3(0.0, bb.size.y * 0.4, bb.position.z + 0.6)
	for i in 10:
		get_tree().create_timer(0.3 * float(i)).timeout.connect(func() -> void:
			if is_inside_tree() and not is_dead:
				FX.engine_start_puff(nose, 1.2))


const VIS_RANGE := {"tank": 3500.0, "gun": 2600.0, "parked": 4200.0, "truck": 2600.0, "tent": 3200.0, "hut": 6000.0, "ammo": 4500.0, "blister": 7000.0}


func _build_intact(root: Node3D) -> void:
	for t in _xf:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.transform = t
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# fade by size: a truck or tent is a speck beyond ~3 km, a parked fighter beyond ~4 km, while hangars and
		# hut rows still read from much further out (they shape the field from altitude)
		var vr: float = float(VIS_RANGE.get(pkind, 7000.0))
		mi.visibility_range_end = vr
		mi.visibility_range_end_margin = vr * 0.12
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)


func _build_wreck(root: Node3D) -> void:
	for t in _xf:
		var tt: Transform3D = t
		var s: Vector3 = _wreck_size * tt.basis.get_scale()
		GroundKit.box(root, s, tt.origin + Vector3(0, s.y * 0.5, 0), wreck_color, Vector3(0, rad_to_deg(tt.basis.get_euler().y), 0))
		if pkind == "parked":   # a snapped tail boom
			GroundKit.box(root, Vector3(1.0, 0.6, s.z * 0.5), tt.origin + Vector3(s.x * 0.4, 0.4, s.z * 0.2), wreck_color.lightened(0.08), Vector3(0, 30, 8))


func _on_destroyed(_killer: Node) -> void:
	if pkind == "ammo" and is_inside_tree():
		# bomb dump cooks off: a few delayed secondary blasts across the site
		for i in 3:
			var p: Vector3 = global_position + Vector3(randf_range(-1.0, 1.0), 2.0, randf_range(-1.0, 1.0)) * hit_radius * 0.8
			get_tree().create_timer(0.3 + 0.4 * float(i)).timeout.connect(func() -> void: GroundKit.explosion(p, 2.4))
