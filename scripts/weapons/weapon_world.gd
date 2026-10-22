class_name WeaponWorld
extends Node
## Autoload "Weapons": owns every live projectile. Pooled, allocation-free in the hot path.
##   Weapons.fire_bullet(pos, vel, team, source, damage, tracer, life)
##   Weapons.drop_bomb(pos, vel, team, source, damage, radius)
##   Weapons.fire_rocket(pos, vel, team, source, damage, radius)
##   Weapons.explode_at(pos, radius, damage, team, source)       # splash (AA shells, ground units, scripts)
##   Weapons.predict_bomb_impact(pos, vel) -> Vector3
## Hit rules: targets are nodes in group "damageable" exposing team / hit_radius / take_damage(amount, source).
## Same-team targets and the firing source are never hit. Terrain via group "terrain" get_height_at().

signal explosion_occurred(pos: Vector3, radius: float)
## The player's hits and kills on anything (ground target or aircraft), for Ops Room taskings and the logbook.
## Emitted by GroundTarget.take_damage / die and Aircraft.take_damage when the source is the player's aircraft.
signal player_hit(node: Node, amount: float)
signal player_kill(node: Node)
## A bomb (or other splash of radius >= 6) fired by the player's aircraft went off. Feeds bomb damage assessment.
signal player_bomb_impact(pos: Vector3, radius: float)


static func is_player_source(src: Node) -> bool:
	return src != null and is_instance_valid(src) and src is Aircraft and (src as Aircraft).player_controlled

const MAX_BULLETS := 700
const MAX_BOMBS := 24
const MAX_ROCKETS := 24
const BOMB_GRAVITY := 30.0
var reservoirs: Array = []   # {c: Vector2 world XZ, r: radius, y: surface} registered by a dam run: the bomb skips on them
const BOMB_DRAG := 0.06
const SKIP_RESTITUTION := 0.6     # vertical speed kept on each bounce off the water
const SKIP_FORWARD_KEEP := 0.9    # horizontal speed kept on each bounce
const SKIP_MIN_BOUNCE := 1.2      # below this rebound speed the bomb stops skipping and sinks
const SKIP_FUSE := 6.0            # seconds underwater before it detonates (shortened for gameplay)
const SKIP_SINK_SPEED := 2.5      # underwater sink rate, m/s
const BULLET_GRAVITY := 3.0
const TRACER_LEN := 10.0
const STRIDE := 16

var bullet_count: int = 0

# --- bullets (struct of arrays) ---
var _bp := PackedVector3Array()
var _bv := PackedVector3Array()
var _blife := PackedFloat32Array()
var _bdmg := PackedFloat32Array()
var _bteam := PackedInt32Array()
var _btracer := PackedByteArray()
var _bsrc: Array = []
var _bmm: MultiMeshInstance3D
var _bbuf := PackedFloat32Array()
var _bnext: int = 0

# --- bombs / rockets ---
var _bombs: Array[WeaponProjectile] = []
var _rockets: Array[WeaponProjectile] = []
var _bomb_pool: Array[WeaponProjectile] = []
var _rocket_pool: Array[WeaponProjectile] = []

# --- target cache ---
var _tn: Array[Node3D] = []
var _tp := PackedVector3Array()
var _tr := PackedFloat32Array()
var _tt := PackedInt32Array()
var _nt: int = 0
var _refresh_t: float = 0.0
# Spatial index (rebuilt on each full refresh, 4x a second): slow / static targets bucketed in GRID-metre cells,
# fast movers (aircraft) and very large targets in a short list that is always checked. A bullet then tests a
# handful of targets instead of every damageable object in the world.
const GRID: float = 300.0
var _grid: Dictionary = {}          # Vector2i -> Array[int] (target indices)
var _movers := PackedInt32Array()
var _grid_top: float = -1.0e9       # highest point of any gridded target (+ margin): bullets above it skip the grid
var _terrain: Node


static func team_id(t: String) -> int:
	if t == "Allies":
		return 0
	if t == "Axis":
		return 1
	return 2


func _ready() -> void:
	process_priority = 5
	_bp.resize(MAX_BULLETS)
	_bv.resize(MAX_BULLETS)
	_blife.resize(MAX_BULLETS)
	_bdmg.resize(MAX_BULLETS)
	_bteam.resize(MAX_BULLETS)
	_btracer.resize(MAX_BULLETS)
	_bsrc.resize(MAX_BULLETS)
	_bbuf.resize(MAX_BULLETS * STRIDE)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, TRACER_LEN)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	mm.instance_count = MAX_BULLETS
	mm.visible_instance_count = 0
	_bmm = MultiMeshInstance3D.new()
	_bmm.multimesh = mm
	_bmm.custom_aabb = AABB(Vector3(-2.0e6, -2.0e4, -2.0e6), Vector3(4.0e6, 4.0e4, 4.0e6))   # whole map (the dams are at x ~ 573 km)
	_bmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bmm)
	for i in MAX_BOMBS:
		var b := WeaponProjectile.new()
		b.node = _make_bomb_node()
		b.node.visible = false
		add_child(b.node)
		_bomb_pool.append(b)
	for i in MAX_ROCKETS:
		var r := WeaponProjectile.new()
		r.node = _make_rocket_node()
		r.node.visible = false
		add_child(r.node)
		_rocket_pool.append(r)


func _make_bomb_node() -> Node3D:
	var root := Node3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.7
	body.height = 3.4
	var mi := ToonUtil.make_mesh(body, Color(0.2, 0.22, 0.18), {"outline_thickness": 0.05})
	mi.rotation.x = deg_to_rad(90.0)
	root.add_child(mi)
	var fin := BoxMesh.new()
	fin.size = Vector3(1.9, 0.12, 0.8)
	var f1 := ToonUtil.make_mesh(fin, Color(0.3, 0.3, 0.25), {"outline": false})
	f1.position = Vector3(0, 0, 1.6)
	root.add_child(f1)
	var f2 := ToonUtil.make_mesh(fin, Color(0.3, 0.3, 0.25), {"outline": false})
	f2.position = Vector3(0, 0, 1.6)
	f2.rotation.z = deg_to_rad(90.0)
	root.add_child(f2)
	return root


func _make_rocket_node() -> Node3D:
	var root := Node3D.new()
	var body := CylinderMesh.new()
	body.top_radius = 0.22
	body.bottom_radius = 0.22
	body.height = 3.0
	var mi := ToonUtil.make_mesh(body, Color(0.55, 0.55, 0.5), {"outline_thickness": 0.03})
	mi.rotation.x = deg_to_rad(90.0)
	root.add_child(mi)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.22
	tip.height = 0.8
	var ti := ToonUtil.make_mesh(tip, Color(0.7, 0.25, 0.15), {"outline": false})
	ti.rotation.x = deg_to_rad(90.0)
	ti.position = Vector3(0, 0, -1.8)
	root.add_child(ti)
	return root


func _terrain_node() -> Node:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")
	return _terrain


func ground_height(pos: Vector3) -> float:
	var t: Node = _terrain_node()
	if t and t.has_method("get_height_at"):
		return t.call("get_height_at", pos)
	return 0.0


func _over_water(pos: Vector3) -> bool:
	var t: Node = _terrain_node()
	if t and t.has_method("is_water_at"):
		return t.call("is_water_at", pos)
	return false


# ------------------------------------------------------------------ spawning

func fire_bullet(pos: Vector3, vel: Vector3, team: String, source: Node, damage: float, tracer: bool = true, life: float = 1.7) -> void:
	var i: int
	if bullet_count < MAX_BULLETS:
		i = bullet_count
		bullet_count += 1
	else:
		i = _bnext
		_bnext = (_bnext + 1) % MAX_BULLETS
	_bp[i] = pos
	_bv[i] = vel
	_blife[i] = life
	_bdmg[i] = damage
	_bteam[i] = team_id(team)
	_btracer[i] = 1 if tracer else 0
	_bsrc[i] = source


var skip_serial: int = 0                  # counts bouncing bombs released (the bomb cam starts on each new one)
var last_skip: WeaponProjectile = null


## For the camera: the newest bouncing bomb and whether it is still in flight.
func skip_bomb_view() -> Dictionary:
	var live: bool = last_skip != null and _bombs.has(last_skip)
	return {"serial": skip_serial, "live": live, "pos": last_skip.pos if live else Vector3.ZERO, "vel": last_skip.vel if live else Vector3.ZERO,
		"skips": last_skip.skips if last_skip != null else 0, "sunk": live and last_skip.sunk}


func drop_bomb(pos: Vector3, vel: Vector3, team: String, source: Node, damage: float = 140.0, radius: float = 26.0) -> void:
	var b: WeaponProjectile = _acquire(_bomb_pool, _bombs)
	if b == null:
		return
	b.reset(pos, vel, team_id(team), source, damage, radius, 40.0)
	# an aircraft flagged "upkeep" (Dam Busters) drops a bouncing bomb instead of a gravity bomb
	b.skipping = source != null and source.has_meta("upkeep") and bool(source.get_meta("upkeep"))
	b.skips = 0
	b.sunk = false
	b.fuse = 0.0
	if b.skipping:
		skip_serial += 1
		last_skip = b
	b.node.visible = true
	b.node.global_position = pos
	FX.sfx("bomb_whistle", pos, -6.0, 0.4)


func fire_rocket(pos: Vector3, vel: Vector3, team: String, source: Node, damage: float = 95.0, radius: float = 18.0) -> void:
	var r: WeaponProjectile = _acquire(_rocket_pool, _rockets)
	if r == null:
		return
	r.reset(pos, vel, team_id(team), source, damage, radius, 3.2)
	r.node.visible = true
	r.node.global_position = pos
	FX.sfx("rocket", pos, -4.0, 0.15)


func _acquire(pool: Array[WeaponProjectile], active: Array[WeaponProjectile]) -> WeaponProjectile:
	if pool.is_empty():
		return null
	var p: WeaponProjectile = pool.pop_back()
	active.append(p)
	return p


func _release(p: WeaponProjectile, active: Array[WeaponProjectile], pool: Array[WeaponProjectile], idx: int) -> void:
	p.node.visible = false
	p.source = null
	active.remove_at(idx)
	pool.append(p)


func active_projectiles() -> int:
	return bullet_count + _bombs.size() + _rockets.size()


# ------------------------------------------------------------------ targets

func _refresh_targets(full: bool) -> void:
	if full:
		var nodes: Array[Node] = get_tree().get_nodes_in_group("damageable")
		_tn.clear()
		var n: int = nodes.size()
		_tp.resize(n)
		_tr.resize(n)
		_tt.resize(n)
		_nt = 0
		for nd in nodes:
			var n3 := nd as Node3D
			if n3 == null or not n3.is_inside_tree():
				continue
			var t: Variant = n3.get("team")
			var r: Variant = n3.get("hit_radius")
			_tn.append(n3)
			_tt[_nt] = team_id(str(t) if t != null else "Neutral")
			_tr[_nt] = float(r) if r != null else 3.0
			_nt += 1
	for i in _nt:
		var nd2: Node3D = _tn[i]
		if is_instance_valid(nd2):
			_tp[i] = nd2.global_position
		else:
			_tr[i] = -1.0
	if full:
		_build_grid()


func _build_grid() -> void:
	_grid.clear()
	_movers = PackedInt32Array()
	_grid_top = -1.0e9
	for i in _nt:
		if _tr[i] < 0.0:
			continue
		if _tn[i] is Aircraft or _tr[i] > GRID * 0.4:
			_movers.append(i)
			continue
		var p: Vector3 = _tp[i]
		var key := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
		var arr: Variant = _grid.get(key)
		if arr == null:
			arr = []
			_grid[key] = arr
		(arr as Array).append(i)
		_grid_top = maxf(_grid_top, p.y + _tr[i] + 60.0)


## Returns segment parameter of first contact between segment a->b and sphere (c, r), or -1.
static func seg_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> float:
	var d: Vector3 = b - a
	var f: Vector3 = a - c
	var cc: float = f.dot(f) - r * r
	if cc <= 0.0:
		return 0.0
	var aa: float = d.dot(d)
	if aa < 1.0e-8:
		return -1.0
	var bb: float = f.dot(d)
	var disc: float = bb * bb - aa * cc
	if disc < 0.0:
		return -1.0
	var t: float = (-bb - sqrt(disc)) / aa
	if t >= 0.0 and t <= 1.0:
		return t
	return -1.0


## Nearest enemy hit along a segment; returns index into target cache or -1. t_out[0] = param.
func _find_hit(a: Vector3, b: Vector3, team: int, src: Variant, extra_r: float, out_t: PackedFloat32Array) -> int:
	var best: int = -1
	var best_t: float = 2.0
	for k in _movers:
		if k >= _nt or _tt[k] == team or _tr[k] < 0.0 or _tn[k] == src:
			continue
		var t: float = seg_sphere(a, b, _tp[k], _tr[k] + extra_r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = k
	if minf(a.y, b.y) < _grid_top and not _grid.is_empty():
		var m: Vector3 = (a + b) * 0.5
		var cx: int = floori(m.x / GRID)
		var cz: int = floori(m.z / GRID)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var arr: Variant = _grid.get(Vector2i(cx + dx, cz + dz))
				if arr == null:
					continue
				for k2 in (arr as Array):
					if k2 >= _nt or _tt[k2] == team or _tr[k2] < 0.0 or _tn[k2] == src:
						continue
					var t2: float = seg_sphere(a, b, _tp[k2], _tr[k2] + extra_r)
					if t2 >= 0.0 and t2 < best_t:
						best_t = t2
						best = k2
	out_t[0] = best_t
	return best


# ------------------------------------------------------------------ splash

func explode_at(pos: Vector3, radius: float, damage: float, team: String, source: Node = null, direct: Node = null) -> void:
	_refresh_targets(true)
	var tid: int = team_id(team)
	for k in _nt:
		if _tt[k] == tid or _tr[k] < 0.0:
			continue
		var nd: Node3D = _tn[k]
		if nd == source:
			continue
		var d: float = maxf(pos.distance_to(_tp[k]) - _tr[k], 0.0)
		var full: bool = nd == direct
		if d >= radius and not full:
			continue
		var f: float = 1.0 if full else 1.0 - d / radius
		if nd.has_method("take_damage"):
			nd.call("take_damage", damage * lerpf(0.25, 1.0, f), source)
	var ry: float = _reservoir_y(pos)
	var in_res: bool = ry > -1.0e8 and pos.y <= ry + 3.0
	var water: bool = in_res or (_over_water(pos) and pos.y < 3.0)
	if water:
		var wpos: Vector3 = Vector3(pos.x, ry if in_res else maxf(pos.y, 0.0), pos.z)
		if radius >= 6.0:
			FX.water_plume(wpos, radius * 0.5)        # bombs / Upkeep: the tall white column
		else:
			FX.water_splash(wpos, radius * 0.5)
			FX.explosion(wpos + Vector3(0, 1, 0), radius * 0.45)
	else:
		FX.explosion(pos, radius * 0.85)
		FX.crater(pos, radius * 0.45)
		if radius >= 15.0:
			FX.smoke_column(pos, radius * 0.18, 10.0)
		FX.dust(pos, radius * 0.5)
		if radius >= 12.0:
			CityFires.ignite(pos, radius / 26.0)      # bombs falling on a town start fires that burn for minutes
	explosion_occurred.emit(pos, radius)
	if radius >= 6.0 and source != null and is_player_source(source):
		player_bomb_impact.emit(pos, radius)


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if active_projectiles() == 0:
		_bmm.multimesh.visible_instance_count = 0
		return
	_refresh_t -= delta
	_refresh_targets(_refresh_t <= 0.0)
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
	_step_bullets(delta)
	_step_bombs(delta)
	_step_rockets(delta)


func _step_bullets(delta: float) -> void:
	var hit_t := _hit_t
	var i: int = 0
	while i < bullet_count:
		var p0: Vector3 = _bp[i]
		var v: Vector3 = _bv[i]
		v.y -= BULLET_GRAVITY * delta
		var p1: Vector3 = p0 + v * delta
		var life: float = _blife[i] - delta
		var remove: bool = life <= 0.0
		if not remove:
			var bs: Variant = _bsrc[i]
			if bs != null and not is_instance_valid(bs):
				bs = null
				_bsrc[i] = null
			var bonus: float = 3.5 if (bs != null and bs is Aircraft and (bs as Aircraft).player_controlled) else 0.0   # forgiving hits for the player
			var k: int = _find_hit(p0, p1, _bteam[i], bs, bonus, hit_t)
			if k >= 0:
				var hp: Vector3 = p0.lerp(p1, hit_t[0])
				var nd: Node3D = _tn[k]
				if is_instance_valid(nd) and nd.has_method("take_damage"):
					if nd is Aircraft:
						(nd as Aircraft)._pending_hit = hp       # where it struck, for holes and part damage
						(nd as Aircraft)._pending_dir = (p1 - p0).normalized()
					nd.call("take_damage", _bdmg[i], bs as Node)
				FX.sparks(hp, (p0 - p1).normalized(), 3)
				FX.sfx("hit", hp, -8.0, 0.08)
				remove = true
			elif p1.y < 600.0:
				var h: float = ground_height(p1)
				if p1.y <= h:
					var gp := Vector3(p1.x, h, p1.z)
					if _over_water(gp):
						FX.water_splash(gp, 1.6)
					else:
						FX.sparks(gp, Vector3.UP, 2)
						FX.dust(gp, 1.4)
					remove = true
		if remove:
			var last: int = bullet_count - 1
			if i != last:
				_bp[i] = _bp[last]
				_bv[i] = _bv[last]
				_blife[i] = _blife[last]
				_bdmg[i] = _bdmg[last]
				_bteam[i] = _bteam[last]
				_btracer[i] = _btracer[last]
				_bsrc[i] = _bsrc[last]
			_bsrc[last] = null
			bullet_count = last
			continue
		_bp[i] = p1
		_bv[i] = v
		_blife[i] = life
		i += 1
	_write_bullets()


var _hit_t := PackedFloat32Array([0.0])


func _write_bullets() -> void:
	var n: int = bullet_count
	for i in n:
		var o: int = i * STRIDE
		if _btracer[i] == 0:
			for j in 12:
				_bbuf[o + j] = 0.0
			_bbuf[o + 15] = 0.0
			continue
		var v: Vector3 = _bv[i]
		var dir: Vector3 = v.normalized()
		var side: Vector3 = dir.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up: Vector3 = side.cross(dir)
		# basis columns: x = side, y = up, z = -dir (box long axis is Z)
		var z: Vector3 = -dir
		_bbuf[o] = side.x
		_bbuf[o + 1] = up.x
		_bbuf[o + 2] = z.x
		_bbuf[o + 3] = _bp[i].x
		_bbuf[o + 4] = side.y
		_bbuf[o + 5] = up.y
		_bbuf[o + 6] = z.y
		_bbuf[o + 7] = _bp[i].y
		_bbuf[o + 8] = side.z
		_bbuf[o + 9] = up.z
		_bbuf[o + 10] = z.z
		_bbuf[o + 11] = _bp[i].z
		if _bteam[i] == 1:
			_bbuf[o + 12] = 3.2     # above 1.0 so tracers glow under the bloom pass
			_bbuf[o + 13] = 1.0
			_bbuf[o + 14] = 0.6
		else:
			_bbuf[o + 12] = 3.2
			_bbuf[o + 13] = 2.6
			_bbuf[o + 14] = 0.9
		_bbuf[o + 15] = 1.0
	_bmm.multimesh.buffer = _bbuf
	_bmm.multimesh.visible_instance_count = n


static func _orient(node: Node3D, vel: Vector3, pos: Vector3) -> void:
	var dir: Vector3 = vel.normalized()
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	node.global_transform = Transform3D(Basis.looking_at(dir, up), pos)


func _step_bombs(delta: float) -> void:
	var i: int = _bombs.size() - 1
	while i >= 0:
		var b: WeaponProjectile = _bombs[i]
		b.age += delta
		if b.skipping:
			_step_skip_bomb(b, i, delta)
			i -= 1
			continue
		var v: Vector3 = b.vel
		v.y -= BOMB_GRAVITY * delta
		var damp: float = maxf(1.0 - BOMB_DRAG * delta, 0.0)
		v.x *= damp
		v.z *= damp
		b.vel = v
		var p1: Vector3 = b.pos + v * delta
		var boom: bool = false
		var direct: Node = null
		if b.age > 0.12:
			var k: int = _find_hit(b.pos, p1, b.team, b.source if is_instance_valid(b.source) else null, 0.0, _hit_t)
			if k >= 0:
				p1 = b.pos.lerp(p1, _hit_t[0])
				direct = _tn[k]
				boom = true
		if not boom:
			var h: float = ground_height(p1)
			if p1.y <= h:
				p1.y = h
				boom = true
			elif b.age > b.max_age:
				boom = true
		b.pos = p1
		if boom:
			var src: Node = b.source if is_instance_valid(b.source) else null
			var dmg: float = b.damage
			var rad: float = b.radius
			var tm: String = ["Allies", "Axis", "Neutral"][b.team]
			_release(b, _bombs, _bomb_pool, i)
			explode_at(p1, rad, dmg, tm, src, direct)
		else:
			_orient(b.node, v, p1)
			if not b.whistled and b.age > 0.6:
				b.whistled = true
		i -= 1


## Bouncing bomb: falls to the water, skips (each bounce loses vertical speed), then sinks and detonates on a
## fuse. A hit on a structure (the dam wall) while it is still in the air or underwater sets it off at once.
func _step_skip_bomb(b: WeaponProjectile, i: int, delta: float) -> void:
	var v: Vector3 = b.vel
	v.y -= BOMB_GRAVITY * delta
	if b.sunk:
		v.y = maxf(v.y, -SKIP_SINK_SPEED)
		v.x *= maxf(1.0 - 0.8 * delta, 0.0)
		v.z *= maxf(1.0 - 0.8 * delta, 0.0)
	b.vel = v
	var p1: Vector3 = b.pos + v * delta
	var boom: bool = false
	var direct: Node = null
	if b.age > 0.12:
		var k: int = _find_hit(b.pos, p1, b.team, b.source if is_instance_valid(b.source) else null, 0.0, _hit_t)
		if k >= 0:
			p1 = b.pos.lerp(p1, _hit_t[0])
			direct = _tn[k]
			boom = true
	if not boom:
		var ry: float = _reservoir_y(p1)
		var water: bool = ry > -1.0e8 or _over_water(p1)
		var surface: float = ry if ry > -1.0e8 else (maxf(ground_height(p1), 0.0) if water else ground_height(p1))
		if water and not b.sunk and p1.y <= surface and v.y <= 0.0:
			p1.y = surface
			if not b.sunk and -v.y >= SKIP_MIN_BOUNCE:
				# skip: rebound, keep most of the forward speed, splash
				b.skips += 1
				v.y = -v.y * SKIP_RESTITUTION
				v.x *= SKIP_FORWARD_KEEP
				v.z *= SKIP_FORWARD_KEEP
				FX.water_splash(p1, 2.2)
				FX.sfx("bomb_whistle", p1, -14.0, 0.3)
			else:
				# too slow to skip any more: sink, and start the underwater fuse
				b.sunk = true
				v.y = -SKIP_SINK_SPEED
				v.x *= 0.5
				v.z *= 0.5
				if b.fuse <= 0.0:
					b.fuse = SKIP_FUSE
				FX.water_splash(p1, 1.4)
			b.vel = v
		elif not water and p1.y <= surface:
			p1.y = surface
			boom = true                     # hit land
		if b.sunk:
			b.fuse -= delta
			if b.fuse <= 0.0:
				boom = true
		if b.age > b.max_age:
			boom = true
	b.pos = p1
	if boom:
		var src: Node = b.source if is_instance_valid(b.source) else null
		var dmg: float = b.damage
		var rad: float = b.radius
		var tm: String = ["Allies", "Axis", "Neutral"][b.team]
		_release(b, _bombs, _bomb_pool, i)
		explode_at(p1, rad, dmg, tm, src, direct)
	else:
		_orient(b.node, v, p1)

func _step_rockets(delta: float) -> void:
	var i: int = _rockets.size() - 1
	while i >= 0:
		var r: WeaponProjectile = _rockets[i]
		r.age += delta
		var v: Vector3 = r.vel
		v.y -= 6.0 * delta
		r.vel = v
		var p1: Vector3 = r.pos + v * delta
		var boom: bool = r.age > r.max_age
		var direct: Node = null
		var k: int = _find_hit(r.pos, p1, r.team, r.source if is_instance_valid(r.source) else null, 1.0, _hit_t)
		if k >= 0:
			p1 = r.pos.lerp(p1, _hit_t[0])
			direct = _tn[k]
			boom = true
		elif p1.y < 600.0:
			var h: float = ground_height(p1)
			if p1.y <= h:
				p1.y = h
				boom = true
		# smoke trail
		r.acc += delta
		while r.acc >= 0.03:
			r.acc -= 0.03
			FX.puffs.spawn(p1 - v.normalized() * 1.5, Vector3(0, 0.6, 0), 1.6, 0.6, 1.8,
				Color(0.85, 0.85, 0.82, 0.8), Color(0.7, 0.7, 0.7, 0.0), 1.0, 0.0, 0.5)
		r.pos = p1
		if boom:
			var src: Node = r.source if is_instance_valid(r.source) else null
			var dmg: float = r.damage
			var rad: float = r.radius
			var tm: String = ["Allies", "Axis", "Neutral"][r.team]
			_release(r, _rockets, _rocket_pool, i)
			explode_at(p1, rad, dmg, tm, src, direct)
		else:
			_orient(r.node, v, p1)
		i -= 1


# ------------------------------------------------------------------ prediction (bombsight)

## Where a bomb released at pos with velocity vel would land (same integrator as the real thing).
func predict_bomb_impact(pos: Vector3, vel: Vector3) -> Vector3:
	var p: Vector3 = pos
	var v: Vector3 = vel
	var dt: float = 0.1
	for s in 120:
		v.y -= BOMB_GRAVITY * dt
		var damp: float = 1.0 - BOMB_DRAG * dt
		v.x *= damp
		v.z *= damp
		var np: Vector3 = p + v * dt
		var h: float = ground_height(np)
		if np.y <= h:
			var f: float = clampf((p.y - h) / maxf(p.y - np.y, 0.0001), 0.0, 1.0)
			var out: Vector3 = p.lerp(np, f)
			out.y = h
			return out
		p = np
	return p


## Surface height of a registered reservoir under p, or -1e9 when p is not over one.
func _reservoir_y(p: Vector3) -> float:
	for rv in reservoirs:
		if Vector2(p.x, p.z).distance_to(rv["c"]) <= float(rv["r"]):
			var ry: float = float(rv["y"])
			return ground_height(p) + 0.4 if ry < 0.0 else ry   # y < 0: the lake follows the terrain under it
	return -1.0e9
