extends Node
## Battle ruins (autoload `BattleDamage`): wherever a fight is staged (tank battles, ship skirmishes, bombing, shelling)
## the buildings nearby are left as WW2 ruins. The ground-battle and sea-battle code only call the API below.
##
##   BattleDamage.ruin_area(world_pos, radius_m, intensity = 1.0, seed = 0)   ruin the buildings within radius_m
##   BattleDamage.crater(world_pos, size_m)                                  one shell / bomb crater
##   BattleDamage.on_blast(world_pos, blast_radius_m)                        a bomb / big shell burst: craters in the
##                                                                           open, a small ruined patch in a built-up area
##   BattleDamage.scar_at(world_pos, radius_m = 0.0) -> bool                 is there a scar there?
##   BattleDamage.clear()                                                    forget every scar (tests, new sortie)
##
## How it works (all of it additive to the dated bomb damage of WarDamage):
##  * Houses: a scar is a live "battle area" in WarDamage (centre, radius, level). Every tile and town built while the
##    scar exists swaps a share of its houses for the gutted-shell meshes (WarDamage.apply_to_houses: roofless shells with
##    a jagged gable, blackened window holes, a standing chimney breast, charred rafters, rubble spilling into the street)
##    or clears the plot, so a scar placed before a tile streams in is applied when the tile is made. Tiles and towns that
##    are already built are re-made in the background (WorldPopulator.battle_refresh: the old tile stays until the new one
##    is ready), so buildings change under the scar at once.
##  * Ground: the terrain shader's bomb-damage zone (rubble wash, scorch, crater fields) is raised under the scar.
##  * Debris: while the player is within a few km each scar gets one node: MultiMesh craters with raised rims, scorch
##    patches, rubble piles, broken wall fragments, leaning chimney stacks (and a burnt barn frame in open country),
##    plus lingering black smoke columns (ten to twenty minutes) and a few small fires that burn out in 1-4 minutes.
##    The node is freed again beyond ~8 km, so a far scar costs a few numbers in an array; its fires and smoke are not
##    restarted when it comes back (they run on the scar's own clock).
##  * Persistent for the session (scars are not saved with a game).
## The cel-shaded style needs nothing special: the meshes use the same vertex-coloured scenery material as the houses.

const MAX_SCARS: int = 60
const MAX_CRATERS: int = 200
const SPAWN_EXTRA: float = 5500.0       # a scar's debris is made when the player is closer than radius + this
const FREE_EXTRA: float = 8000.0        # and freed beyond radius + this
const SMOKE_LIFE: float = 900.0         # seconds a smoke column keeps rising (x 0.6 - 1.4)
const FIRE_MIN: float = 70.0
const FIRE_MAX: float = 260.0
const MAX_NODES_PER_TICK: int = 2

var _scars: Array = []            # {id, x, z, r, k, seed, born, fire_t, em: Array, crater_only, size}
var _nodes: Dictionary = {}       # id -> Node3D
var _next_id: int = 1
var _dirty: Array = []            # [Vector3 pos, radius] circles whose buildings / ground must be re-made
var _clock: float = 0.0
var _timer: float = 0.0
var _pop: Node = null
var stat_refresh_calls: int = 0   # for tests / debug


# ------------------------------------------------------------------ API

func ruin_area(world_pos: Vector3, radius_m: float, intensity: float = 1.0, seed: int = 0) -> void:
	var k: float = clampf(intensity, 0.0, 1.0)
	if k <= 0.02 or radius_m < 6.0:
		return
	var r: float = minf(radius_m, 1500.0)
	var c: Vector2 = Vector2(world_pos.x, world_pos.z)
	# a fight keeps calling this from the same spot: fold it into the scar that is already there
	for s in _scars:
		if bool(s["crater_only"]):
			continue
		if Vector2(float(s["x"]), float(s["z"])).distance_to(c) < minf(float(s["r"]), r) * 0.6:
			var new_r: float = maxf(float(s["r"]), r)
			var new_k: float = minf(1.0, maxf(float(s["k"]), k) + 0.08 * minf(float(s["k"]), k))
			var changed: bool = new_r > float(s["r"]) * 1.1 or new_k > float(s["k"]) + 0.08
			if changed:
				var old_r: float = float(s["r"])
				s["r"] = new_r
				s["k"] = new_k
				s["fire_t"] = _clock
				_free_node(s)
				_sync()
				_mark_dirty(Vector3(float(s["x"]), 0.0, float(s["z"])), maxf(old_r, new_r))
			return
	var sd: int = seed if seed != 0 else ((int(world_pos.x) * 73856093) ^ (int(world_pos.z) * 19349663))
	var row: Dictionary = {"id": _next_id, "x": world_pos.x, "z": world_pos.z, "r": r, "k": k, "seed": sd, "born": _clock,
		"fire_t": _clock, "em": [], "crater_only": false, "size": 0.0}
	_next_id += 1
	_scars.append(row)
	_trim()
	_sync()
	_mark_dirty(world_pos, r)


## One shell / bomb crater (size_m = diameter). Craters alone never ruin houses.
func crater(world_pos: Vector3, size_m: float) -> void:
	if size_m < 1.5:
		return
	for s in _scars:
		if bool(s["crater_only"]) and Vector2(float(s["x"]) - world_pos.x, float(s["z"]) - world_pos.z).length() < maxf(float(s["size"]), size_m) * 0.5:
			return          # the same hole again
	var row: Dictionary = {"id": _next_id, "x": world_pos.x, "z": world_pos.z, "r": 0.0, "k": 0.0, "seed": _next_id * 7919,
		"born": _clock, "fire_t": _clock, "em": [], "crater_only": true, "size": minf(size_m, 40.0)}
	_next_id += 1
	_scars.append(row)
	var n_c: int = 0
	for s2 in _scars:
		if bool(s2["crater_only"]):
			n_c += 1
	if n_c > MAX_CRATERS:
		for i in _scars.size():
			if bool(_scars[i]["crater_only"]):
				_free_node(_scars[i])
				_scars.remove_at(i)
				break


## A burst from a bomb / big shell: in a built-up area it ruins a patch round the hit (a 250 kg bomb gutted the houses
## on both sides of the street), in the open it leaves a crater. Called from Weapons.explode_at.
func on_blast(world_pos: Vector3, blast_radius: float) -> void:
	if blast_radius < 5.0:
		return
	if _built_up(world_pos):
		if blast_radius >= 9.0:
			ruin_area(world_pos, blast_radius * 3.6, clampf(blast_radius / 40.0, 0.3, 0.8), 0)
		crater(world_pos, blast_radius * 0.9)
	else:
		crater(world_pos, blast_radius * 0.9)


func scar_at(world_pos: Vector3, radius_m: float = 0.0) -> bool:
	for s in _scars:
		var d: float = Vector2(float(s["x"]) - world_pos.x, float(s["z"]) - world_pos.z).length()
		var rr: float = float(s["size"]) * 0.5 if bool(s["crater_only"]) else float(s["r"])
		if d <= rr + radius_m:
			return true
	return false


## Forget every scar (tests, a new sortie). The buildings come back the next time their tiles are made.
func clear() -> void:
	for s in _scars:
		if not bool(s["crater_only"]):
			_mark_dirty(Vector3(float(s["x"]), 0.0, float(s["z"])), float(s["r"]))
		_free_node(s)
	_scars.clear()
	_sync()


func scar_count() -> int:
	return _scars.size()


func live_node_count() -> int:
	return _nodes.size()


## Ruin level (0..1) a scar gives the buildings at a point (tests).
func level_at(world_pos: Vector3) -> float:
	return WarDamage.level_at(world_pos.x, world_pos.z)


# ------------------------------------------------------------------ plumbing

func _trim() -> void:
	var n: int = 0
	for s in _scars:
		if not bool(s["crater_only"]):
			n += 1
	if n <= MAX_SCARS:
		return
	for i in _scars.size():
		if not bool(_scars[i]["crater_only"]):
			_free_node(_scars[i])
			_mark_dirty(Vector3(float(_scars[i]["x"]), 0.0, float(_scars[i]["z"])), float(_scars[i]["r"]))
			_scars.remove_at(i)
			break


## Hand the battle areas to WarDamage (the houses of every tile built from now on) as a new array.
func _sync() -> void:
	var list: Array = []
	for s in _scars:
		if bool(s["crater_only"]):
			continue
		list.append([Vector2(float(s["x"]), float(s["z"])), float(s["r"]), clampf(0.25 + 0.75 * float(s["k"]), 0.0, 1.0)])
	WarDamage.set_battle(list)


func _mark_dirty(pos: Vector3, r: float) -> void:
	_dirty.append([pos, r])


func _populator() -> Node:
	if _pop != null and is_instance_valid(_pop):
		return _pop
	var t: SceneTree = get_tree()
	_pop = t.get_first_node_in_group("world_populator") if t != null else null
	return _pop


static func _built_up(p: Vector3) -> bool:
	if LandCover.ready() and LandCover.class_at(p.x, p.z) == 50:
		return true
	return not CityFires.city_at(p).is_empty()


func _process(delta: float) -> void:
	_clock += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	if not _dirty.is_empty():
		var pop: Node = _populator()
		if pop != null and pop.has_method("battle_refresh"):
			var todo: Array = _dirty
			_dirty = []
			for e in todo:
				pop.call("battle_refresh", e[0], float(e[1]))
				stat_refresh_calls += 1
		else:
			_dirty.clear()          # no world yet: the tiles are made with the scar in place
	_stream()
	_expire_emitters()


func _stream() -> void:
	var pl: Node3D = GroundKit.player_node()
	if pl == null or not pl.is_inside_tree():
		return
	var p: Vector3 = pl.global_position
	var made: int = 0
	for s in _scars:
		var big: float = float(s["r"])
		var d: float = Vector2(p.x - float(s["x"]), p.z - float(s["z"])).length()
		var has: bool = _nodes.has(int(s["id"]))
		var reach: float = (3500.0 if bool(s["crater_only"]) else SPAWN_EXTRA)
		if not has and d < big + reach:
			if made < MAX_NODES_PER_TICK:
				_spawn(s)
				made += 1
		elif has and d > big + (reach + 2500.0):
			_free_node(s)


func _free_node(s: Dictionary) -> void:
	var id: int = int(s["id"])
	if _nodes.has(id):
		var n: Node = _nodes[id]
		_nodes.erase(id)
		if is_instance_valid(n):
			n.queue_free()
	s["em"] = []


func _spawn(s: Dictionary) -> void:
	var n: Node3D = _build_crater_node(s) if bool(s["crater_only"]) else build_scar_node(s)
	if n == null:
		return
	add_child(n)
	_nodes[int(s["id"])] = n
	if not bool(s["crater_only"]):
		add_smoke_and_fires(s, n)


## Stop smoke columns and fires whose time is up (the emitters are bound to holders inside the scar node).
func _expire_emitters() -> void:
	for s in _scars:
		var em: Array = s["em"]
		for i in range(em.size() - 1, -1, -1):
			var e: Dictionary = em[i]
			var age: float = _clock - float(e["t0"])
			if age >= float(e["life"]):
				for x in (e["list"] as Array):
					if x != null and is_instance_valid(x):
						(x as FXEmitter).stop()
				em.remove_at(i)


# ------------------------------------------------------------------ the scar node

static func _rand_pt(rng: RandomNumberGenerator, cx: float, cz: float, reach: float, centre_bias: float = 0.8) -> Vector3:
	var a: float = rng.randf() * TAU
	var d: float = reach * pow(rng.randf(), centre_bias)
	var x: float = cx + cos(a) * d
	var z: float = cz + sin(a) * d
	return Vector3(x, GroundKit.ground_y(x, z), z)


static func _dry(p: Vector3) -> bool:
	return GroundKit.raw_y(p.x, p.z) >= 1.5


## The debris, smoke and fires of one scar. Deterministic for the scar (its seed), so it comes back the same.
func build_scar_node(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "BattleScar%d" % int(s["id"])
	var cx: float = float(s["x"])
	var cz: float = float(s["z"])
	var r: float = float(s["r"])
	var k: float = float(s["k"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"])
	var open_country: bool = not (LandCover.ready() and LandCover.class_at(cx, cz) == 50)
	var craters: Array = []
	var scorch: Array = []
	var rubble: Array = []
	var walls: Array = []
	var stacks: Array = []
	var frames: Array = []
	for i in clampi(int(r / 16.0 * k) + 1, 1, 18):
		var p: Vector3 = _rand_pt(rng, cx, cz, r * 0.92)
		if not _dry(p):
			continue
		var sz: float = rng.randf_range(3.0, 9.5)
		craters.append(Scatter._xf(p + Vector3(0, -0.02 * sz, 0), rng.randf() * TAU, Vector3(sz, clampf(sz * 0.16, 0.6, 1.4), sz)))
		if rng.randf() < 0.6:
			var sc: float = rng.randf_range(9.0, 20.0)
			var q: Vector3 = p + Vector3(rng.randf_range(-4.0, 4.0), 0.0, rng.randf_range(-4.0, 4.0))
			scorch.append(Scatter._xf(Vector3(q.x, GroundKit.ground_y(q.x, q.z) + 0.05, q.z), rng.randf() * TAU, Vector3(sc, 1.0, sc * rng.randf_range(0.6, 1.0))))
	for i2 in clampi(int(r / 7.0 * k) + 2, 2, 46):
		var p2: Vector3 = _rand_pt(rng, cx, cz, r * 0.85, 0.7)
		if not _dry(p2):
			continue
		var w: float = rng.randf_range(2.2, 6.0)
		rubble.append(Scatter._xf(p2, rng.randf() * TAU, Vector3(w, rng.randf_range(0.8, 1.7), w * rng.randf_range(0.7, 1.2))))
		if rng.randf() < 0.5:
			var p3: Vector3 = _rand_pt(rng, cx, cz, r * 0.8, 0.7)
			if _dry(p3):
				var wl: float = rng.randf_range(2.5, 6.5)
				walls.append(Scatter._xf(p3, rng.randf() * TAU, Vector3(wl, rng.randf_range(1.6, 3.4), 1.3)))
	for i3 in clampi(int(r / 45.0 * k) + 1, 1, 8):
		var p4: Vector3 = _rand_pt(rng, cx, cz, r * 0.75, 0.8)
		if not _dry(p4):
			continue
		var tilt: Basis = Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_euler(Vector3(rng.randf_range(-0.07, 0.07), 0.0, rng.randf_range(-0.07, 0.07)))
		stacks.append(Transform3D(tilt * Basis.from_scale(Vector3(1.2, rng.randf_range(4.5, 7.5), 1.2)), p4))
	if open_country:
		for i4 in 1 + int(k > 0.6):
			var p5: Vector3 = _rand_pt(rng, cx, cz, r * 0.5)
			if _dry(p5):
				frames.append(Scatter._xf(p5, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.9, 1.25)))
	if not craters.is_empty():
		root.add_child(Scatter.multi(crater_mesh(), craters, 3500.0, false))
	if not scorch.is_empty():
		root.add_child(Scatter.multi(scorch_mesh(), scorch, 3500.0, false))
	if not rubble.is_empty():
		root.add_child(Scatter.multi(rubble_mesh(), rubble, 4200.0, false))
	if not walls.is_empty():
		root.add_child(Scatter.multi(wall_mesh(), walls, 4200.0, false))
	if not stacks.is_empty():
		root.add_child(Scatter.multi(chimney_mesh(), stacks, 4500.0, false))
	if not frames.is_empty():
		root.add_child(Scatter.multi(barn_frame_mesh(), frames, 4500.0, false))
	return root


## Black smoke columns (long lived, thinning over ten to twenty minutes) and a few small fires (one to four minutes),
## on the scar's own clock: a scar that streams back in resumes where it was. `root` must already be in the tree.
func add_smoke_and_fires(s: Dictionary, root: Node3D) -> void:
	var cx: float = float(s["x"])
	var cz: float = float(s["z"])
	var r: float = float(s["r"])
	var k: float = float(s["k"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) ^ 0x5bd1e995
	var em: Array = []
	var n_s: int = clampi(1 + int(k * r / 130.0), 1, 3)
	for i in n_s:
		var life: float = SMOKE_LIFE * rng.randf_range(0.6, 1.4)
		var age: float = _clock - float(s["born"])
		var p: Vector3 = _rand_pt(rng, cx, cz, r * 0.7)
		if age >= life or not _dry(p):
			continue
		var h := Node3D.new()
		h.name = "Smoke%d" % i
		root.add_child(h)
		h.position = p
		var e: FXEmitter = FX.pillar(h, 2.4 + 2.2 * k + rng.randf_range(0.0, 1.0))
		if e != null:
			em.append({"list": [e], "t0": float(s["born"]), "life": life})
	var n_f: int = clampi(int(k * r / 200.0), 0, 2) + (1 if k > 0.5 else 0)
	for j in n_f:
		var flife: float = rng.randf_range(FIRE_MIN, FIRE_MAX)
		var fp: Vector3 = _rand_pt(rng, cx, cz, r * 0.6)
		if _clock - float(s["fire_t"]) >= flife or not _dry(fp):
			continue
		var fh := Node3D.new()
		fh.name = "Fire%d" % j
		root.add_child(fh)
		fh.position = fp
		var fl: Array = FX.blaze(fh, rng.randf_range(0.7, 1.3), 0.7, true)
		em.append({"list": fl, "t0": float(s["fire_t"]), "life": flife})
	s["em"] = em


func _build_crater_node(s: Dictionary) -> Node3D:
	var sz: float = float(s["size"])
	var p: Vector3 = Vector3(float(s["x"]), 0.0, float(s["z"]))
	if not _dry(Vector3(p.x, GroundKit.raw_y(p.x, p.z), p.z)):
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Crater%d" % int(s["id"])
	mi.mesh = crater_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"])
	mi.transform = Scatter._xf(Vector3(p.x, GroundKit.ground_y(p.x, p.z) - 0.02 * sz, p.z), rng.randf() * TAU, Vector3(sz, clampf(sz * 0.16, 0.6, 1.4), sz))
	mi.visibility_range_end = 2600.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.name = "CraterNode%d" % int(s["id"])
	holder.add_child(mi)
	return holder


# ------------------------------------------------------------------ meshes (unit size, cached in Scatter._meshes)

static func _cached(key: String) -> ArrayMesh:
	return Scatter._meshes[key] if Scatter._meshes.has(key) else null


## A crater: a raised rim of thrown earth round a dark scorched floor (unit diameter, rim 0.2 tall).
static func crater_mesh() -> ArrayMesh:
	var m: ArrayMesh = _cached("bd_crater")
	if m != null:
		return m
	var parts: Array = []
	parts.append(GroundKit.cyl_part(0.40, 0.52, 0.20, Vector3(0, 0.10, 0), Color(0.20, 0.15, 0.10), Vector3.ZERO, 12, false))
	parts.append(GroundKit.cyl_part(0.30, 0.30, 0.03, Vector3(0, 0.205, 0), Color(0.012, 0.010, 0.009), Vector3.ZERO, 12, false))
	parts.append(GroundKit.box_part(Vector3(0.16, 0.12, 0.10), Vector3(0.42, 0.14, 0.12), Color(0.24, 0.18, 0.12), Vector3(0, 25, 6), false))
	parts.append(GroundKit.box_part(Vector3(0.12, 0.10, 0.14), Vector3(-0.38, 0.12, -0.20), Color(0.18, 0.14, 0.10), Vector3(0, -30, -5), false))
	m = AirfieldAssets._build(parts)
	Scatter._meshes["bd_crater"] = m
	return m


## A scorch mark: a black, ragged disc a hand above the ground (unit diameter).
static func scorch_mesh() -> ArrayMesh:
	var m: ArrayMesh = _cached("bd_scorch")
	if m != null:
		return m
	var parts: Array = []
	parts.append(GroundKit.cyl_part(0.50, 0.50, 0.04, Vector3(0, 0.02, 0), Color(0.015, 0.013, 0.011), Vector3.ZERO, 10, false))
	parts.append(GroundKit.cyl_part(0.34, 0.34, 0.05, Vector3(0.12, 0.025, -0.08), Color(0.03, 0.025, 0.02), Vector3.ZERO, 8, false))
	m = AirfieldAssets._build(parts)
	Scatter._meshes["bd_scorch"] = m
	return m


## A rubble pile: tumbled brick, a slab of masonry, charred planks and a splintered beam (about 1 m wide, 1 m tall).
static func rubble_mesh() -> ArrayMesh:
	var m: ArrayMesh = _cached("bd_rubble")
	if m != null:
		return m
	var brick := Color(0.36, 0.25, 0.19)
	var stone := Color(0.40, 0.36, 0.31)
	var soot := Color(0.10, 0.09, 0.08)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(0.95, 0.34, 0.80), Vector3(0, 0.14, 0), stone.darkened(0.1), Vector3(0, 12, 0), false))
	parts.append(GroundKit.box_part(Vector3(0.62, 0.34, 0.52), Vector3(0.10, 0.36, 0.04), brick, Vector3(6, 32, 10), false))
	parts.append(GroundKit.box_part(Vector3(0.34, 0.26, 0.30), Vector3(-0.22, 0.46, -0.08), stone, Vector3(-8, 50, 12), false))
	parts.append(GroundKit.box_part(Vector3(0.28, 0.20, 0.24), Vector3(0.28, 0.58, 0.08), brick.darkened(0.2), Vector3(14, 8, -9), false))
	parts.append(GroundKit.box_part(Vector3(0.50, 0.04, 0.12), Vector3(-0.05, 0.62, 0.22), soot, Vector3(10, 28, 22), false))
	parts.append(GroundKit.box_part(Vector3(0.08, 0.08, 0.95), Vector3(0.20, 0.50, 0.05), soot, Vector3(16, -20, 8), false))
	parts.append(GroundKit.box_part(Vector3(0.40, 0.16, 0.22), Vector3(-0.36, 0.10, 0.34), brick, Vector3(0, -34, 4), false))
	parts.append(GroundKit.box_part(Vector3(0.22, 0.12, 0.30), Vector3(0.40, 0.08, -0.34), stone, Vector3(0, 40, 0), false))
	m = AirfieldAssets._build(parts)
	Scatter._meshes["bd_rubble"] = m
	return m


## A broken wall: a jagged run of brick with a blackened window hole and a lintel hanging (unit length, unit tall,
## about 0.2 m thick before the instance's z scale).
static func wall_mesh() -> ArrayMesh:
	var m: ArrayMesh = _cached("bd_wall")
	if m != null:
		return m
	var brick := Color(0.35, 0.24, 0.18)
	var soot := Color(0.09, 0.08, 0.07)
	var hole := Color(0.05, 0.05, 0.05)
	var parts: Array = []
	var hs: Array = [0.45, 0.80, 1.0, 0.62, 0.34]
	var segw: float = 0.2
	for i in hs.size():
		var h: float = float(hs[i])
		var x: float = -0.5 + segw * (float(i) + 0.5)
		parts.append(GroundKit.box_part(Vector3(segw * 1.01, h, 0.20), Vector3(x, h * 0.5, 0), brick, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(segw * 1.02, 0.05, 0.22), Vector3(x, h - 0.025, 0), soot, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.14, 0.26, 0.24), Vector3(-0.10, 0.50, 0), hole, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.30, 0.18, 0.5), Vector3(0.0, 0.09, 0.30), brick.darkened(0.15), Vector3(0, 0, 8), false))     # fallen courses at its foot
	m = AirfieldAssets._build(parts)
	Scatter._meshes["bd_wall"] = m
	return m


## A chimney stack left standing: tapering brick, sooted top, broken courses (unit footprint 0.5 m, unit height; scale
## y by the stack's height).
static func chimney_mesh() -> ArrayMesh:
	var m: ArrayMesh = _cached("bd_chimney")
	if m != null:
		return m
	var brick := Color(0.34, 0.22, 0.17)
	var soot := Color(0.09, 0.08, 0.07)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(0.62, 0.10, 0.62), Vector3(0, 0.05, 0), brick.darkened(0.1), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.46, 0.55, 0.46), Vector3(0, 0.37, 0), brick, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.38, 0.28, 0.38), Vector3(0, 0.78, 0), brick, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.30, 0.08, 0.36), Vector3(0.03, 0.96, 0), soot, Vector3(0, 0, 6), false))
	parts.append(GroundKit.box_part(Vector3(0.12, 0.06, 0.40), Vector3(0, 0.22, 0), soot, Vector3.ZERO, false))
	m = AirfieldAssets._build(parts)
	Scatter._meshes["bd_chimney"] = m
	return m


## A burnt-out barn in open country, at real size (about 13 x 7 m, 6 m to the ridge): charred posts, a few rafters still
## up in a broken A, the fallen roof in a heap, an ash floor and the stump of its brick base. Not scaled per instance.
static func barn_frame_mesh() -> ArrayMesh:
	var m: ArrayMesh = _cached("bd_barn")
	if m != null:
		return m
	var charred := Color(0.08, 0.065, 0.05)
	var charred2 := Color(0.16, 0.11, 0.08)
	var ash := Color(0.13, 0.12, 0.11)
	var brick := Color(0.33, 0.22, 0.17)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(13.0, 0.12, 7.0), Vector3(0, 0.06, 0), ash, Vector3.ZERO, false))
	for ix in 4:
		var x: float = -5.4 + 3.6 * float(ix)
		for sz in [-1.0, 1.0]:
			var hh: float = [4.2, 2.6, 5.0, 1.8][ix] * (1.0 if sz < 0.0 else 0.8)
			parts.append(GroundKit.box_part(Vector3(0.32, hh, 0.32), Vector3(x, hh * 0.5, sz * 3.2), charred, Vector3(0, 0, [2, -4, 3, 7][ix]), false))
	parts.append(GroundKit.box_part(Vector3(0.22, 0.22, 7.0), Vector3(-1.8, 5.1, 0), charred, Vector3(0, 0, 0), false))
	parts.append(GroundKit.box_part(Vector3(0.20, 3.9, 0.20), Vector3(-1.8, 3.4, 1.7), charred2, Vector3(-38, 0, 0), false))
	parts.append(GroundKit.box_part(Vector3(0.20, 3.2, 0.20), Vector3(-1.8, 3.1, -1.8), charred, Vector3(41, 0, 0), false))
	parts.append(GroundKit.box_part(Vector3(0.20, 4.4, 0.20), Vector3(1.8, 1.6, 1.0), charred2, Vector3(-62, 20, 8), false))
	parts.append(GroundKit.box_part(Vector3(7.0, 0.7, 2.6), Vector3(1.2, 0.5, -1.0), charred2, Vector3(0, 14, 7), false))        # the fallen roof
	parts.append(GroundKit.box_part(Vector3(4.2, 0.5, 2.2), Vector3(-2.6, 0.4, 1.2), charred, Vector3(0, -22, -5), false))
	parts.append(GroundKit.box_part(Vector3(0.5, 0.6, 7.0), Vector3(-6.4, 0.3, 0), brick, Vector3.ZERO, false))                 # the brick base, broken
	parts.append(GroundKit.box_part(Vector3(0.5, 0.35, 7.0), Vector3(6.4, 0.18, 0), brick, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(13.0, 0.3, 0.5), Vector3(0, 0.15, -3.4), brick, Vector3.ZERO, false))
	m = AirfieldAssets._build(parts)
	Scatter._meshes["bd_barn"] = m
	return m


# ------------------------------------------------------------------ debug: --ruin-test=<lat,lon | town:id>[,radius[,delay s[,intensity]]]

## Stage a ruined area at the given place after `delay` seconds (default 0: as soon as the world is up, so the tile
## being made, or already built, shows the scar). Pair it with --air --freeze --at=lat,lon and --look=lat,lon,dist,height,yaw.
func debug_start(host: Node, arg: String) -> void:
	var parts: PackedStringArray = arg.substr(arg.find("=") + 1).split(",")
	var centre: Vector3 = Vector3.ZERO
	var used: int = 1
	if parts[0].begins_with("town:"):
		var want: String = parts[0].substr(5).to_lower()
		var pop: Node = _populator()
		var loc: Variant = pop.get("loc") if pop != null else null
		if loc is Dictionary:
			for c in (loc as Dictionary).get("cities", []):
				if str(c.get("id", "")).to_lower() == want or str(c.get("name", "")).to_lower() == want:
					centre = WorldCoords.latlon_to_world(float(c["lat"]), float(c["lon"]))
	else:
		centre = WorldCoords.latlon_to_world(float(parts[0]), float(parts[1]) if parts.size() > 1 else 0.0)
		used = 2
	var r: float = float(parts[used]) if parts.size() > used else 260.0
	var delay: float = float(parts[used + 1]) if parts.size() > used + 1 else 0.0
	var k: float = float(parts[used + 2]) if parts.size() > used + 2 else 1.0
	get_tree().create_timer(maxf(delay, 0.2)).timeout.connect(func() -> void:
		ruin_area(centre, r, k, 7)
		for i in 5:
			var a: float = float(i) * 1.37
			crater(centre + Vector3(cos(a), 0.0, sin(a)) * r * 0.4, 6.0 + float(i))
		print("[ruin-test] ruined %.0f m round %.0f, %.0f (level %.2f, scars %d)" % [r, centre.x, centre.z, level_at(centre), scar_count()]))
