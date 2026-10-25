class_name CityFires
extends Node3D
## Fires that take hold where a town is bombed. Any big blast that lands in a built-up area (bombs, V-1s, V-2s,
## the distant blitz) lights a fire there: flames, a flickering glow on the streets and a leaning black plume.
## Fires close together merge and grow; once a town has several, a huge pall of smoke rises over it. Fires burn
## for several minutes, then die down. A capped, pooled manager: CityFires.ignite(pos, strength).

const MAX_FIRES: int = 30
const MAX_PALLS: int = 6
const MERGE_DIST: float = 220.0

static var _inst: CityFires = null

var _fires: Array = []        # {node, light, glow, emit:Array, life, max_life, power, city, seed}
var _palls: Dictionary = {}   # city name -> {node, emit}
var _cities: Array = []       # {name, pos, r}
var _cities_ready: bool = false
var _t: float = 0.0
var _halo_mat: StandardMaterial3D


static func get_instance() -> CityFires:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var t: SceneTree = GroundKit.tree()
	if t == null:
		return null
	_inst = CityFires.new()
	_inst.name = "CityFires"
	var parent: Node = t.current_scene if t.current_scene else t.root
	parent.add_child(_inst)
	return _inst


## Light (or feed) a fire at pos. strength ~1 for a bomb, 2 for a V-1, 3 for a V-2. Outside a town nothing happens
## unless `anywhere` is set. Returns true when a fire burns there now.
static func ignite(pos: Vector3, strength: float = 1.0, anywhere: bool = false) -> bool:
	var cf: CityFires = get_instance()
	if cf == null:
		return false
	return cf._ignite(pos, strength, anywhere)


## The town (name, centre, radius) whose built-up area contains pos, or {} if none.
static func city_at(pos: Vector3) -> Dictionary:
	var cf: CityFires = get_instance()
	if cf == null:
		return {}
	return cf._city_at(pos)


static func cities() -> Array:
	var cf: CityFires = get_instance()
	if cf == null:
		return []
	cf._load_cities()
	return cf._cities


func _ready() -> void:
	top_level = true
	# the orange glow a burning street throws up into its own smoke: an additive billboard, seen from miles off at night
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.vertex_color_use_as_albedo = false
	_halo_mat.albedo_texture = _halo_tex()
	_halo_mat.albedo_color = Color(1.0, 0.45, 0.12, 0.0)
	_halo_mat.disable_receive_shadows = true
	# fade where the billboard meets the ground, or hills slice the glow off in a hard straight edge
	_halo_mat.proximity_fade_enabled = true
	_halo_mat.proximity_fade_distance = 45.0


static func _halo_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _load_cities() -> void:
	if _cities_ready:
		return
	var pop: Node = get_tree().get_first_node_in_group("world_populator")
	if pop == null:
		return
	_cities_ready = true
	var loc: Variant = pop.get("loc")
	if not (loc is Dictionary):
		return
	for c in (loc as Dictionary).get("cities", []):
		var d: Dictionary = c
		if not bool(d.get("in_bounds", true)):
			continue
		var p: Vector3 = WorldCoords.latlon_to_world(float(d["lat"]), float(d["lon"]))
		var sz: float = float(d.get("size", 1))
		var r: float = (90.0 + sz * 85.0) * (1.6 + sz * 0.9)     # the whole built-up area, not just the core (London ~3 km)
		_cities.append({"name": str(d.get("name", d.get("id", "town"))), "pos": p, "r": r, "size": int(d.get("size", 1))})


func _city_at(pos: Vector3) -> Dictionary:
	_load_cities()
	var best: Dictionary = {}
	var best_k: float = 1.0
	for c in _cities:
		var k: float = Vector2(pos.x - (c["pos"] as Vector3).x, pos.z - (c["pos"] as Vector3).z).length() / float(c["r"])
		if k < best_k:
			best_k = k
			best = c
	return best


func _ignite(pos: Vector3, strength: float, anywhere: bool) -> bool:
	var city: Dictionary = _city_at(pos)
	if city.is_empty() and not anywhere:
		return false
	if FX.is_water(pos):
		return false
	var gp := Vector3(pos.x, GroundKit.ground_y(pos.x, pos.z), pos.z)
	# feed a fire that is already burning close by
	for f in _fires:
		if is_instance_valid(f["node"]) and (f["node"] as Node3D).global_position.distance_to(gp) < MERGE_DIST:
			f["power"] = minf(float(f["power"]) + strength * 0.6, 4.0)
			f["life"] = maxf(float(f["life"]), float(f["max_life"]) * 0.8)
			if float(f["power"]) >= 2.5 and not bool(f["pillar"]):
				f["pillar"] = true
				(f["emit"] as Array).append(FX.pillar(f["node"], 8.0 + float(f["power"]) * 1.5))
			return true
	while _fires.size() >= MAX_FIRES:
		_kill(0)
	var n := Node3D.new()
	n.name = "CityFire"
	add_child(n)
	n.global_position = gp
	# a whole block alight, big enough to be seen burning from ten miles off
	var sz: float = clampf(3.2 + strength * 1.4, 3.2, 8.0)
	var emit: Array = FX.blaze(n, sz, 0.9 + strength * 0.25)
	# a second, taller fire bound to the same holder (bound emitters are never culled by the FX emitter cap)
	emit.append(FX._add_emitter(FXEmitter.Kind.FIRE, gp, n, Vector3(randf_range(-25, 25), 0.0, randf_range(-25, 25)), sz * 2.2, -1.0))
	var pillar: bool = strength >= 2.5
	if pillar:
		emit.append(FX.pillar(n, 9.0 + strength * 1.5))
	# a modest light for the walls and smoke right by the fire. The old one reached 300-400 m and its clustered
	# lighting lit a hard-edged red square of ground and trees; the wide firelight on the ground is the soft
	# GroundGlow pool instead.
	# (no omni light, ground glow or glow halo any more: the red reflections showed as blinking red squares from
	# a distance. The flames and the smoke plume carry the fire.)
	var l: OmniLight3D = null
	var glow: GroundGlow = null
	var life: float = randf_range(300.0, 540.0) * (0.8 + 0.2 * strength)
	_fires.append({"node": n, "light": l, "glow": glow, "emit": emit, "life": life, "max_life": life, "power": strength,
		"pillar": pillar, "city": str(city.get("name", "")), "seed": randf() * 10.0, "cpos": city.get("pos", gp)})
	_update_pall(str(city.get("name", "")))
	return true


## A town with several fires gets one great pall of smoke rising over its centre.
func _update_pall(cname: String) -> void:
	if cname == "" or _palls.has(cname):
		return
	var n_fires: int = 0
	var centre := Vector3.ZERO
	for f in _fires:
		if str(f["city"]) == cname and is_instance_valid(f["node"]):
			n_fires += 1
			centre += (f["node"] as Node3D).global_position
	if n_fires < 3 or _palls.size() >= MAX_PALLS:
		return
	centre /= float(n_fires)
	var h := Node3D.new()
	h.name = "CityPall"
	add_child(h)
	h.global_position = centre
	_palls[cname] = {"node": h, "emit": [FX.pillar(h, 16.0)]}


func _kill(i: int) -> void:
	var f: Dictionary = _fires[i]
	for e in f["emit"]:
		if e != null:
			(e as FXEmitter).stop()
	if is_instance_valid(f["node"]):
		(f["node"] as Node).queue_free()
	_fires.remove_at(i)


func _process(delta: float) -> void:
	_t += delta
	var night: float = FX.night_factor()
	_halo_mat.albedo_color.a = 0.55 * night * (0.85 + 0.15 * sin(_t * 6.0))
	for i in range(_fires.size() - 1, -1, -1):
		var f: Dictionary = _fires[i]
		if not is_instance_valid(f["node"]):
			_fires.remove_at(i)
			continue
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			_kill(i)
			continue
		# the glow flickers, and fades as the fire burns itself out
		var fade: float = clampf(float(f["life"]) / 60.0, 0.0, 1.0)
		var sd: float = float(f["seed"])
		var fl: float = 0.75 + 0.18 * sin(_t * 8.0 + sd) + 0.1 * sin(_t * 21.0 + sd * 3.0)
		if f["light"] != null and is_instance_valid(f["light"]):
			(f["light"] as OmniLight3D).light_energy = (0.4 + 2.2 * night) * fl * fade * (0.7 + 0.15 * float(f["power"]))
		var g: Variant = f.get("glow")
		if g != null and is_instance_valid(g):
			(g as GroundGlow).intensity = (0.08 + 0.62 * night) * fade * clampf(0.6 + 0.15 * float(f["power"]), 0.6, 1.2)
	# a pall stays while its town still burns
	for cname in _palls.keys():
		var alive: bool = false
		for f in _fires:
			if str(f["city"]) == cname:
				alive = true
				break
		if not alive:
			var p: Dictionary = _palls[cname]
			for e in p["emit"]:
				(e as FXEmitter).stop()
			if is_instance_valid(p["node"]):
				(p["node"] as Node).queue_free()
			_palls.erase(cname)


func fire_count() -> int:
	return _fires.size()
