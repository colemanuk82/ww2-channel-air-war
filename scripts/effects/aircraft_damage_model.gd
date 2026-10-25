class_name AircraftDamageModel
extends Node
## Where an aircraft has been hit, what it does to the handling, and what you can see.
##  * Every hit lands on a part: port wing, starboard wing, tail, engine or cockpit (from where the round struck,
##    in the aircraft's own frame). Flak and blast damage spread a few fragments over the side facing the burst.
##  * Handling: a holed wing loses lift and drags that wing down (the pilot holds it against the stick); a wing hit
##    hard enough loses its aileron (roll rate drops); a damaged tail makes pitch and yaw sluggish and wandering;
##    engine hits cost power; every hole adds drag.
##  * Visible: bullet holes and torn panels are projected Decals placed on the model's real surface - each hit
##    snaps to the nearest sampled vertex of the aircraft's own meshes and is oriented to that vertex's normal, so
##    they sit flush on every type (fat radial cowlings, thin elliptical wings, twin booms). A lost aileron leaves
##    a ragged gap at the wing's trailing edge. In the cockpit the canopy cracks where it was hit and oil smears the
##    windscreen when the engine is hit.
## Repaired (parts and holes cleared) when the aircraft is reset or self-repairs to full health.

const PARTS := ["wing_l", "wing_r", "tail", "engine", "cockpit"]
const MAX_DECALS: int = 60
const AILERON_AT: float = 0.6

static var _samples: Dictionary = {}        # model_id -> {"p": PackedVector3Array, "n": PackedVector3Array, "ext": Vector3}
static var _tex_hole: Array = []            # a few variants
static var _tex_tear: Texture2D

var aircraft: Aircraft
var parts: Dictionary = {"wing_l": 0.0, "wing_r": 0.0, "tail": 0.0, "engine": 0.0, "cockpit": 0.0}
var aileron_lost: Dictionary = {"wing_l": false, "wing_r": false}
var _decals: Array = []
var _told: Dictionary = {}
var _overlay: CanvasLayer
var _glass: Control
var _cracks: Array = []                      # [{p: Vector2 (0..1 screen), seed}]
var _oil: float = 0.0
var _wander_t: float = 0.0

# ---- structural failure and engine loss
var wing_lost: Dictionary = {"wing_l": 0, "wing_r": 0}      # 0 whole, 1 outer half gone, 2 whole wing gone
var tail_lost: bool = false
var eng_x: Array = []             # aircraft-local x of each engine (multi-engine types only)
var eng_hp: Array = []            # damage to each engine, 0..1
var eng_out: Array = []           # which engines have failed
var eng_r: Array = []
var eng_z: Array = []
var _eng_fx: Array = []
var _eng_ready: bool = false
var _hidden: Array = []
var _cut_cache: Vector3 = Vector3.ZERO


func attach(a: Aircraft) -> void:
	aircraft = a


# ------------------------------------------------------------------ handling (read by Aircraft every frame)

func roll_auth_k() -> float:
	var k: float = 1.0 - 0.22 * engines_out_frac()
	for w in ["wing_l", "wing_r"]:
		if int(wing_lost[w]) == 1:
			k -= 0.25
	for w in ["wing_l", "wing_r"]:
		k -= 0.12 * float(parts[w])
		if bool(aileron_lost[w]):
			k -= 0.3
	return clampf(k, 0.35, 1.0)


func pitch_auth_k() -> float:
	return clampf((1.0 - 0.45 * float(parts["tail"])) * (1.0 - 0.18 * engines_out_frac()), 0.4, 1.0)


## Turning ability: a one-engined twin or a wing with its tip gone will not turn as hard.
func turn_k() -> float:
	var k: float = 1.0 - 0.32 * engines_out_frac()
	for w in ["wing_l", "wing_r"]:
		if int(wing_lost[w]) == 1:
			k -= 0.3
	return clampf(k, 0.3, 1.0)


func engines_out_frac() -> float:
	if eng_out.is_empty():
		return 0.0
	var n: int = 0
	for o in eng_out:
		if bool(o):
			n += 1
	return float(n) / float(eng_out.size())


## Net sideways thrust imbalance: + when the starboard engines are the ones that are out (the nose swings that way).
func engine_asym() -> float:
	if eng_out.is_empty():
		return 0.0
	var a: float = 0.0
	for i in eng_out.size():
		if bool(eng_out[i]):
			a += signf(float(eng_x[i]))
	return a / float(eng_out.size())


## Roll the damaged wing drops toward (rad/s at full authority). + = right.
func roll_bias() -> float:
	var d: float = float(parts["wing_r"]) - float(parts["wing_l"])
	if bool(aileron_lost["wing_r"]):
		d += 0.35
	if bool(aileron_lost["wing_l"]):
		d -= 0.35
	# half a wing gone: the aircraft rolls hard toward the missing side and the pilot cannot hold it
	d += 3.4 * float(int(wing_lost["wing_r"]) == 1) - 3.4 * float(int(wing_lost["wing_l"]) == 1)
	d += 0.35 * engine_asym()
	return deg_to_rad(16.0) * clampf(d, -4.0, 4.0)


## A shot-up tail makes the nose hunt about a little.
func yaw_wander(delta: float) -> float:
	var asym: float = engine_asym()
	if asym != 0.0:
		var thr: float = clampf(aircraft.throttle, 0.2, 1.0)
		var b: float = deg_to_rad(7.0) * asym * thr
		if aircraft.state == Aircraft.State.ALIVE:
			return b + _wander_yaw(delta)
	return _wander_yaw(delta)


func _wander_yaw(delta: float) -> float:
	var t: float = float(parts["tail"])
	if t < 0.2:
		return 0.0
	_wander_t += delta
	return deg_to_rad(5.0) * t * sin(_wander_t * 1.7) * sin(_wander_t * 0.63 + 1.0)


func engine_k() -> float:
	var k: float = clampf(1.0 - 0.45 * smoothstep(0.15, 1.0, float(parts["engine"])), 0.5, 1.0)
	var f: float = engines_out_frac()
	if f > 0.0:
		k *= (1.0 - 0.7 * f) if f < 1.0 else 0.12        # each dead engine costs its share of the power
	return k


func drag_k() -> float:
	var holes: float = float(parts["wing_l"]) + float(parts["wing_r"]) + 0.5 * float(parts["tail"])
	var lost: float = 0.0
	for w in ["wing_l", "wing_r"]:
		lost += 0.2 * float(mini(int(wing_lost[w]), 1))
	return 1.0 + 0.12 * holes + (0.08 if bool(aileron_lost["wing_l"]) else 0.0) + (0.08 if bool(aileron_lost["wing_r"]) else 0.0) + lost + 0.1 * engines_out_frac()


func any_damage() -> bool:
	if engines_out_frac() > 0.0 or int(wing_lost["wing_l"]) > 0 or int(wing_lost["wing_r"]) > 0 or tail_lost:
		return true
	for p in PARTS:
		if float(parts[p]) > 0.0:
			return true
	return false


# ------------------------------------------------------------------ hits

## world_pos / dir: where the round struck and which way it was travelling (Vector3.ZERO when unknown: flak, blast).
var _last_source: Node = null


func on_hit(amount: float, source: Node, world_pos: Vector3, dir: Vector3) -> void:
	_last_source = source
	if aircraft == null or aircraft._model == null or not aircraft.is_inside_tree():
		return
	var smp: Dictionary = _get_samples()
	if smp.is_empty():
		return
	var inv: Transform3D = aircraft.global_transform.affine_inverse()
	var share: float = clampf(amount / maxf(aircraft.stats.max_health, 1.0), 0.0, 1.0)
	if world_pos != Vector3.ZERO:
		var lp: Vector3 = inv * world_pos
		var ld: Vector3 = (inv.basis * dir).normalized() if dir != Vector3.ZERO else Vector3.ZERO
		var i: int = _nearest_sample(smp, lp, ld)
		_hit_at(smp, i, share * 2.2)
	else:
		# flak / blast: a few fragments over the side facing the burst
		var from_l: Vector3 = Vector3.ZERO
		if source != null and is_instance_valid(source) and source is Node3D:
			from_l = (inv * (source as Node3D).global_position).normalized()
		var n: int = clampi(int(1.0 + share * 10.0), 1, 4)
		for k in n:
			var i2: int = _facing_sample(smp, from_l)
			_hit_at(smp, i2, share * 2.2 / float(n))


func _hit_at(smp: Dictionary, i: int, dmg: float) -> void:
	var p: Vector3 = smp["p"][i]
	var nrm: Vector3 = smp["n"][i]
	var part: String = _part_of(p, smp["ext"])
	parts[part] = clampf(float(parts[part]) + dmg, 0.0, 1.0)
	_hit_engines(p, dmg)
	# bigger aircraft carry bigger holes, so they read at the distance you see a bomber from
	var k: float = clampf(float((smp["ext"] as Vector3).x) / 8.0, 1.0, 2.2)
	_add_hole(p, nrm, randf_range(0.6, 0.95) * k)
	# a burst puts a few rounds close together: one or two more holes on the skin nearby
	for _extra in randi_range(0, 2):
		var t: Vector3 = nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
		t = t.rotated(nrm.normalized(), randf() * TAU)
		var j: int = _nearest_sample(smp, p + t * randf_range(0.5, 1.1) * k, Vector3.ZERO)
		_add_hole(smp["p"][j], smp["n"][j], randf_range(0.4, 0.7) * k)
	if part == "cockpit":
		_crack()
	if part == "engine":
		_oil = clampf(_oil + dmg * 1.5, 0.0, 0.85)
	for w in ["wing_l", "wing_r"]:
		if part == w and not bool(aileron_lost[w]) and float(parts[w]) >= AILERON_AT and randf() < 0.75:
			_lose_aileron(w, smp)
	_tell(part)
	_check_breakup(part, _last_source)


## Which part a point (aircraft-local) belongs to. The aircraft faces -Z, +X is starboard.
func _part_of(p: Vector3, ext: Vector3) -> String:
	var span: float = maxf(ext.x, 0.1)
	var length: float = maxf(ext.z, 0.1)
	if absf(p.x) > span * 0.16:
		return "wing_r" if p.x > 0.0 else "wing_l"
	if p.z > length * 0.35:
		return "tail"
	if p.z < -length * 0.28:
		return "engine"
	if p.y > ext.y * 0.15 and absf(p.z) < length * 0.25:
		return "cockpit"
	return "tail" if p.z > 0.0 else "engine"


func _tell(part: String) -> void:
	if not aircraft.player_controlled:
		return
	var msg: String = ""
	if part == "cockpit" and not _told.has("cockpit"):
		msg = "CANOPY HIT"
	elif part == "engine" and float(parts["engine"]) > 0.45 and not _told.has("engine"):
		msg = "ENGINE HIT - LOSING POWER"
	elif part == "tail" and float(parts["tail"]) > 0.5 and not _told.has("tail"):
		msg = "TAIL HIT - CONTROLS SLUGGISH"
	elif part in ["wing_l", "wing_r"] and float(parts[part]) > 0.35 and not _told.has(part):
		msg = "%s WING HOLED - SHE PULLS TO %s" % ["PORT" if part == "wing_l" else "STARBOARD", "PORT" if part == "wing_l" else "STARBOARD"]
	if msg == "":
		return
	_told[part] = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", msg, 3.0)


# ------------------------------------------------------------------ surface samples (per model type, cached)

func _get_samples() -> Dictionary:
	var id: String = String(aircraft.stats.model_id)
	if _samples.has(id):
		return _samples[id]
	var ps := PackedVector3Array()
	var ns := PackedVector3Array()
	var inv: Transform3D = aircraft.global_transform.affine_inverse()
	var skip := ["Propeller", "PropDisc", "Blades", "Canopy", "CockpitEye", "GearL", "GearR"]
	var meshes: Array = aircraft._model.find_children("*", "MeshInstance3D", true, false)
	var total: int = 0
	for m in meshes:
		var mi: MeshInstance3D = m
		if mi.mesh != null:
			total += _vert_count(mi.mesh)
	var stride: int = maxi(1, total / 2500)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for m in meshes:
		var mi: MeshInstance3D = m
		if mi.mesh == null or not mi.visible:
			continue
		var bad: bool = false
		var nd: Node = mi
		while nd != null and nd != aircraft._model:
			if String(nd.name) in skip:
				bad = true
				break
			nd = nd.get_parent()
		if bad:
			continue
		var xf: Transform3D = inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var vn: Variant = arr[Mesh.ARRAY_NORMAL]
			if vn == null or (vn as PackedVector3Array).size() != vs.size():
				continue
			var nn: PackedVector3Array = vn
			var j: int = 0
			while j < vs.size():
				var q: Vector3 = xf * vs[j]
				ps.append(q)
				ns.append((xf.basis * nn[j]).normalized())
				lo = lo.min(q)
				hi = hi.max(q)
				j += stride
	if ps.is_empty():
		return {}
	var ext: Vector3 = Vector3(maxf(absf(lo.x), absf(hi.x)), maxf(absf(lo.y), absf(hi.y)), maxf(absf(lo.z), absf(hi.z)))
	_samples[id] = {"p": ps, "n": ns, "ext": ext}
	return _samples[id]


static func _vert_count(mesh: Mesh) -> int:
	var n: int = 0
	if mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			n += (mesh as ArrayMesh).surface_get_array_len(s)
	return n


## The surface point nearest the bullet's path (facing the shot when the direction is known).
func _nearest_sample(smp: Dictionary, lp: Vector3, ld: Vector3) -> int:
	var ps: PackedVector3Array = smp["p"]
	var ns: PackedVector3Array = smp["n"]
	var best: int = 0
	var bd: float = INF
	for i in ps.size():
		var q: Vector3 = ps[i]
		var dist: float
		if ld != Vector3.ZERO:
			var w: Vector3 = q - lp
			var t: float = w.dot(ld)
			dist = (w - ld * t).length_squared()
			if ns[i].dot(ld) > 0.25:
				dist += 4.0          # prefer skin that faces the incoming round (entry holes)
		else:
			dist = q.distance_squared_to(lp)
		if dist < bd:
			bd = dist
			best = i
	return best


func _facing_sample(smp: Dictionary, from_l: Vector3) -> int:
	var ps: PackedVector3Array = smp["p"]
	var ns: PackedVector3Array = smp["n"]
	for tries in 12:
		var i: int = randi() % ps.size()
		if from_l == Vector3.ZERO or ns[i].dot(from_l) > 0.0:
			return i
	return randi() % ps.size()


# ------------------------------------------------------------------ decals

func _add_hole(p: Vector3, n: Vector3, size: float, tex: Texture2D = null, span_len: float = 0.0) -> void:
	if _decals.size() >= MAX_DECALS:
		var old: Variant = _decals.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var d := Decal.new()
	d.texture_albedo = tex if tex != null else _hole_tex()
	d.size = Vector3(span_len if span_len > 0.0 else size, 0.32, size)          # shallow: never reaches round a thin edge onto the next surface
	d.normal_fade = 0.6                  # fades on skin angled away, so edges of wings and fins don't smear
	d.upper_fade = 0.15
	d.lower_fade = 0.15
	d.albedo_mix = 1.0
	d.distance_fade_enabled = true
	d.distance_fade_begin = 260.0
	d.distance_fade_length = 80.0
	aircraft.add_child(d)
	# the decal projects along its local -Y: lay +Y along the surface normal, spin it randomly about that axis
	var up: Vector3 = (n if n.length() > 0.1 else Vector3.UP).normalized()
	var b: Basis
	if span_len > 0.0:
		# lined up with the wing: X along the span, Z along the chord
		var x: Vector3 = (Vector3.RIGHT - up * Vector3.RIGHT.dot(up)).normalized()
		b = Basis(x, up, x.cross(up).normalized())
	else:
		b = Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, randf() * TAU)
	d.transform = Transform3D(b, p)
	_decals.append(d)


func _lose_aileron(w: String, smp: Dictionary) -> void:
	aileron_lost[w] = true
	var ps: PackedVector3Array = smp["p"]
	var ns: PackedVector3Array = smp["n"]
	var ext: Vector3 = smp["ext"]
	var sgn: float = 1.0 if w == "wing_r" else -1.0
	# the outboard trailing edge: the rearmost point of this wing 60-85% out (any normal - edge vertices face back),
	# then the upper-surface point nearest just inside it carries the gap
	var zte: float = -INF
	for i in ps.size():
		var q: Vector3 = ps[i]
		var f: float = q.x * sgn / maxf(ext.x, 0.1)
		if f > 0.6 and f < 0.85 and q.z > zte:
			zte = q.z
	if zte > -INF:
		var span: float = ext.x
		var target := Vector3(sgn * span * 0.72, 0.0, zte - span * 0.05)
		var best: int = -1
		var bd: float = INF
		for i in ps.size():
			if ns[i].y < 0.5:
				continue
			var dxz: float = Vector2(ps[i].x - target.x, ps[i].z - target.z).length_squared()
			if dxz < bd:
				bd = dxz
				best = i
		if best >= 0:
			var at := Vector3(target.x, ps[best].y, target.z)
			_add_hole(at, ns[best], span * 0.12, _tear_tex(), span * 0.3)
	if aircraft.is_inside_tree():
		FX.debris(aircraft.global_position, 3, 0.5, 18.0, Color(0.3, 0.32, 0.28))
	if aircraft.player_controlled:
		_told[w] = true
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_message"):
			hud.call("show_message", "%s AILERON SHOT AWAY" % ("STARBOARD" if w == "wing_r" else "PORT"), 3.5)


static func _hole_tex() -> Texture2D:
	if _tex_hole.is_empty():
		for v in 3:
			_tex_hole.append(_make_hole(64, v))
	return _tex_hole[randi() % _tex_hole.size()]


## A bullet hole: a dark punched centre, a ring of torn bare aluminium with jagged petals, a little soot.
static func _make_hole(sz: int, variant: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var petals: Array = []
	for k in 9:
		petals.append(rng.randf_range(0.75, 1.35))
	for y in sz:
		for x in sz:
			var u: float = (float(x) + 0.5) / float(sz) * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / float(sz) * 2.0 - 1.0
			var r: float = sqrt(u * u + v * v)
			var a: float = atan2(v, u)
			var pk: float = float(petals[int(fposmod(a / TAU * 9.0, 9.0))])
			var hole_r: float = 0.16 * (0.85 + 0.25 * pk)
			var c := Color(0, 0, 0, 0)
			if r < hole_r:
				c = Color(0.02, 0.02, 0.02, 1.0)
			elif r < hole_r + 0.16 * pk:
				var t: float = (r - hole_r) / (0.16 * pk)
				c = Color(0.62, 0.62, 0.6, 1.0).lerp(Color(0.38, 0.37, 0.35, 1.0), t)     # bare metal petals
			elif r < 0.98:
				var t2: float = clampf((r - hole_r - 0.16 * pk) / 0.5, 0.0, 1.0)
				c = Color(0.07, 0.06, 0.05, clampf(0.8 * (1.0 - t2 * t2), 0.0, 0.8))     # scorched paint round the hole
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## The ragged gap where an aileron was shot away.
static func _tear_tex() -> Texture2D:
	if _tex_tear != null:
		return _tex_tear
	var sz: int = 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var edge: Array = []
	for k in 17:
		edge.append(rng.randf_range(-0.12, 0.12))
	for y in sz:
		for x in sz:
			var u: float = (float(x) + 0.5) / float(sz) * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / float(sz) * 2.0 - 1.0
			var ef: float = clampf((u + 1.0) * 8.0, 0.0, 15.999)
			var ei: int = int(ef)
			var j: float = lerpf(float(edge[ei]), float(edge[mini(ei + 1, 16)]), ef - float(ei))
			var e: float = 0.55 + j - absf(u) * 0.2
			var c := Color(0, 0, 0, 0)
			var d: float = maxf(absf(v) - e, absf(u) - 0.92)
			if d < 0.0:
				c = Color(0.03, 0.03, 0.03, 1.0)
			elif d < 0.08:
				c = Color(0.6, 0.6, 0.58, 1.0)
			elif d < 0.3:
				c = Color(0.08, 0.07, 0.06, 0.5 * (1.0 - d / 0.3))
			img.set_pixel(x, y, c)
	_tex_tear = ImageTexture.create_from_image(img)
	return _tex_tear


# ------------------------------------------------------------------ cockpit: cracked glass, oil

func _crack() -> void:
	if not aircraft.player_controlled:
		return
	_cracks.append({"p": Vector2(randf_range(0.18, 0.82), randf_range(0.12, 0.6)), "seed": randi()})
	if _cracks.size() > 6:
		_cracks.pop_front()
	_ensure_overlay()
	_glass.queue_redraw()


func _ensure_overlay() -> void:
	if _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 3
	add_child(_overlay)
	_glass = Control.new()
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.draw.connect(_draw_glass)
	_overlay.add_child(_glass)


func _process(_delta: float) -> void:
	if _overlay == null:
		if _oil > 0.05 and aircraft != null and aircraft.player_controlled:
			_ensure_overlay()
		return
	_overlay.visible = aircraft != null and aircraft._cockpit_view and aircraft.state == Aircraft.State.ALIVE


func _draw_glass() -> void:
	var sz: Vector2 = _glass.size
	# oil thrown back over the windscreen from a hit engine: brown streaks from the bottom up
	if _oil > 0.05:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for k in int(10 + 30 * _oil):
			var x: float = rng.randf_range(0.2, 0.8) * sz.x
			var h: float = rng.randf_range(0.15, 0.55) * sz.y * _oil
			var w: float = rng.randf_range(6.0, 26.0)
			_glass.draw_rect(Rect2(x - w * 0.5, sz.y * 0.62 - h, w, h), Color(0.18, 0.12, 0.04, 0.05 + 0.1 * _oil * rng.randf()))
	for c in _cracks:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = int(c["seed"])
		var o: Vector2 = (c["p"] as Vector2) * sz
		_glass.draw_circle(o, 5.0, Color(0.9, 0.92, 0.95, 0.55))
		# radial cracks with a kink or two, then a couple of concentric rings
		for k in rng2.randi_range(7, 11):
			var a: float = rng2.randf() * TAU
			var p0: Vector2 = o
			var seg: int = rng2.randi_range(2, 4)
			for s in seg:
				a += rng2.randf_range(-0.35, 0.35)
				var p1: Vector2 = p0 + Vector2(cos(a), sin(a)) * rng2.randf_range(25.0, 90.0)
				_glass.draw_line(p0, p1, Color(0.92, 0.94, 0.97, 0.5 - 0.1 * s), 1.4)
				p0 = p1
		for ring in 2:
			var rr: float = rng2.randf_range(14.0, 40.0) * (ring + 1)
			var a0: float = rng2.randf() * TAU
			_glass.draw_arc(o, rr, a0, a0 + rng2.randf_range(1.5, 4.0), 18, Color(0.9, 0.92, 0.95, 0.3), 1.0)


# ------------------------------------------------------------------ repair

func repair() -> void:
	_reset_structure()
	for p in PARTS:
		parts[p] = 0.0
	aileron_lost = {"wing_l": false, "wing_r": false}
	for d in _decals:
		if is_instance_valid(d):
			(d as Node).queue_free()
	_decals.clear()
	_cracks.clear()
	_oil = 0.0
	_told.clear()
	if _glass != null:
		_glass.queue_redraw()


# ------------------------------------------------------------------ structural failure

func _spec() -> Dictionary:
	return ModelSpecs.get_spec(aircraft.stats.model_id)


func _sc() -> float:
	return float(_spec().get("scale", 1.0))


func _half_span() -> float:
	var sp: Dictionary = _spec()
	if sp.is_empty():
		return 5.5
	return float(sp["wing"]["half"]) * _sc()


func _big() -> float:
	return 0.55 if aircraft.stats.max_health > 300.0 else 1.0       # bombers are built stronger


## A wing or the tail that has taken heavy punishment can fail on a further hit.
func _check_breakup(part: String, source: Node) -> void:
	if aircraft == null or aircraft.state != Aircraft.State.ALIVE or aircraft.invulnerable:
		return
	var lv: float = aircraft.damage_level()
	if part == "tail":
		var t: float = float(parts["tail"])
		if not tail_lost and t >= 0.6 and lv >= 0.35 and randf() < _big() * (0.10 + 0.35 * (t - 0.6) / 0.4 + 0.2 * lv):
			lose_tail(source)
	elif part == "wing_l" or part == "wing_r":
		var w: float = float(parts[part])
		if int(wing_lost[part]) < 2 and w >= 0.5 and lv >= 0.3 and randf() < _big() * (0.08 + 0.35 * (w - 0.5) / 0.5 + 0.2 * lv):
			lose_wing(part, source)


## Called every frame while the aircraft flies: a damaged wing or tail cannot take heavy G or a fast dive.
func structural_check(delta: float) -> void:
	if aircraft.invulnerable or not any_part_weak():
		return
	var g: float = absf(aircraft.g_load)
	var over: float = maxf(aircraft.speed - aircraft.stats.max_speed * 1.08, 0.0) / maxf(aircraft.stats.max_speed, 1.0)
	for w in ["wing_l", "wing_r"]:
		var d: float = float(parts[w])
		if d >= 0.45 and int(wing_lost[w]) < 2:
			var limit: float = 7.2 - 6.0 * d
			if g > limit or over > 0.0:
				if randf() < (0.35 + 0.5 * (g - limit) / 4.0 + 6.0 * over) * delta * _big():
					lose_wing(w, null)
					return
	var t: float = float(parts["tail"])
	if t >= 0.55 and not tail_lost:
		var tl: float = 7.0 - 5.0 * t
		if g > tl or over > 0.0:
			if randf() < (0.3 + 0.4 * (g - tl) / 4.0 + 6.0 * over) * delta * _big():
				lose_tail(null)


func any_part_weak() -> bool:
	return float(parts["wing_l"]) >= 0.45 or float(parts["wing_r"]) >= 0.45 or float(parts["tail"]) >= 0.55


func _say(msg: String) -> void:
	if aircraft.player_controlled:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_message"):
			hud.call("show_message", msg, 4.0)


func lose_wing(w: String, source: Node) -> void:
	var prev: int = int(wing_lost[w])
	var lvl: int = prev + 1
	if lvl == 1 and aircraft.damage_level() > 0.7 and randf() < 0.4:
		lvl = 2
	wing_lost[w] = lvl
	_spawn_wing_piece(w, lvl, prev)
	apply_cut()
	var side: String = "PORT" if w == "wing_l" else "STARBOARD"
	if lvl == 2:
		_say("%s WING GONE!" % side)
		_fail_engines_beyond(w, 0.35)
		aircraft.start_breakup(w, source)
	else:
		_say("%s WING TIP SHEARED OFF - SHE WON'T HOLD" % side)
		_fail_engines_beyond(w, _half_span() * 0.5)


func lose_tail(source: Node) -> void:
	if tail_lost:
		return
	tail_lost = true
	_spawn_tail_pieces()
	apply_cut()
	_say("TAIL SHOT AWAY!")
	aircraft.start_breakup("tail", source)


func _fail_engines_beyond(w: String, x_thr: float) -> void:
	_init_engines()
	var sgn: float = 1.0 if w == "wing_r" else -1.0
	for i in eng_x.size():
		if not bool(eng_out[i]) and float(eng_x[i]) * sgn > x_thr:
			_engine_fail(i, false)


func _spawn_wing_piece(w: String, lvl: int, prev: int) -> void:
	var sp: Dictionary = _spec()
	if sp.is_empty() or aircraft.get_parent() == null:
		return
	var sc: float = _sc()
	var half: float = _half_span()
	var sgn: float = 1.0 if w == "wing_r" else -1.0
	var root: float = maxf(half * 0.09, 0.4)
	var inner: float = half * 0.5 if lvl == 1 else root          # the section that comes off runs from `inner` ...
	var outer: float = half if prev == 0 else half * 0.5          # ... out to `outer` (the tip may already be gone)
	var length: float = maxf(outer - inner, 0.8)
	var chord: float = float(sp["wing"]["cr"]) * sc * 0.8
	var xl: float = sgn * (inner + length * 0.5)
	var zc: float = (float(sp["wing"]["le_z"]) + float(sp["wing"]["cr"]) * 0.5) * sc
	var xf: Transform3D = aircraft.global_transform * Transform3D(Basis.IDENTITY, Vector3(xl, 0.2, zc))
	var out: Vector3 = aircraft.global_transform.basis.x * sgn
	var v: Vector3 = aircraft.velocity * 0.9 + out * 9.0 + Vector3(0.0, 5.0, 0.0)
	FallingPart.make(aircraft.get_parent(), xf, Vector3(length, 0.14 * sc + 0.08, chord), Color(0.32, 0.34, 0.28), v,
		Vector3(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0), sgn * randf_range(2.0, 5.0)))
	FX.debris(xf.origin, 6, 0.6, 16.0, Color(0.34, 0.36, 0.3))
	FX.explosion(xf.origin, 0.5)


func _spawn_tail_pieces() -> void:
	var sp: Dictionary = _spec()
	if sp.is_empty() or aircraft.get_parent() == null:
		return
	var sc: float = _sc()
	var tl: Dictionary = sp["tail"]
	var fin: Dictionary = sp["fin"]
	var zt: float = float(tl["z"]) * sc
	var gb: Transform3D = aircraft.global_transform
	var v0: Vector3 = aircraft.velocity * 0.85
	var xf: Transform3D = gb * Transform3D(Basis.IDENTITY, Vector3(0.0, float(tl["y"]) * sc, zt))
	FallingPart.make(aircraft.get_parent(), xf, Vector3(float(tl["span"]) * sc * 2.0, 0.12 * sc + 0.06, float(tl["cr"]) * sc * 0.8),
		Color(0.32, 0.34, 0.28), v0 + gb.basis.y * 4.0 + gb.basis.x * 3.0, Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0)))
	var xf2: Transform3D = gb * Transform3D(Basis.IDENTITY, Vector3(0.0, float(fin["y"]) * sc + float(fin["h"]) * sc * 0.5, float(fin["z"]) * sc))
	FallingPart.make(aircraft.get_parent(), xf2, Vector3(0.12 * sc + 0.06, float(fin["h"]) * sc, float(fin["cr"]) * sc * 0.8),
		Color(0.32, 0.34, 0.28), v0 + gb.basis.y * 6.0 - gb.basis.x * 4.0, Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0)))
	FX.debris(xf.origin, 8, 0.7, 18.0, Color(0.34, 0.36, 0.3))
	FX.explosion(xf.origin, 0.6)


## Push the current losses into the model: the skin shader discards what has been torn off, and the separate
## parts (markings, flaps, propellers, hole decals) that lie in the lost region are hidden.
func apply_cut() -> void:
	if aircraft == null or aircraft._model == null:
		return
	var sp: Dictionary = _spec()
	var half: float = _half_span()
	var thr_r: float = _wing_thr("wing_r", half)
	var thr_l: float = _wing_thr("wing_l", half)
	var thr_t: float = 0.0
	if tail_lost and not sp.is_empty():
		var sc: float = _sc()
		thr_t = float(sp["tail"]["z"]) * sc - float(sp["tail"]["cr"]) * sc * 0.9
	var inv: Transform3D = aircraft.global_transform.affine_inverse()
	for n in aircraft._model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null:
			continue
		var mat: Material = mi.material_override
		var pbr: bool = mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and str((mat as ShaderMaterial).shader.resource_path).ends_with("aircraft_pbr.gdshader")
		if pbr:
			var mt: Transform3D = mi.global_transform.affine_inverse() * aircraft.global_transform
			var lx_r: float = (mt * Vector3(thr_r, 0.0, 0.0)).x if thr_r > 0.0 else 0.0
			var lx_l: float = -(mt * Vector3(-thr_l, 0.0, 0.0)).x if thr_l > 0.0 else 0.0
			var lz_t: float = (mt * Vector3(0.0, 0.0, thr_t)).z if thr_t > 0.0 else 0.0
			mi.set_instance_shader_parameter("cut", Vector4(maxf(lx_r, 0.001) if thr_r > 0.0 else 0.0, maxf(lx_l, 0.001) if thr_l > 0.0 else 0.0, lz_t if thr_t > 0.0 else 0.0, 0.0))
		else:
			var c: Vector3 = inv * (mi.global_transform * mi.get_aabb().get_center())
			var gone: bool = (thr_r > 0.0 and c.x > thr_r) or (thr_l > 0.0 and c.x < -thr_l) or (thr_t > 0.0 and c.z > thr_t)
			if gone and mi.visible:
				mi.visible = false
				_hidden.append(mi)
	for d in _decals:
		if is_instance_valid(d):
			var dp: Vector3 = (d as Node3D).position
			if (thr_r > 0.0 and dp.x > thr_r) or (thr_l > 0.0 and dp.x < -thr_l) or (thr_t > 0.0 and dp.z > thr_t):
				(d as Node3D).visible = false


func _wing_thr(w: String, half: float) -> float:
	match int(wing_lost[w]):
		1:
			return half * 0.5
		2:
			return maxf(half * 0.09, 0.4)
	return 0.0


# ------------------------------------------------------------------ engines (multi-engined aircraft)

func _init_engines() -> void:
	if _eng_ready:
		return
	_eng_ready = true
	if aircraft.stats.engine_count < 2:
		return
	var sp: Dictionary = _spec()
	if sp.is_empty() or not sp.has("engines"):
		return
	var sc: float = _sc()
	for e in sp["engines"]:
		var ed: Dictionary = e
		if absf(float(ed["x"])) < 0.3:
			continue
		eng_x.append(float(ed["x"]) * sc)
		eng_z.append(Vector2(float(ed["z0"]), float(ed["z1"])) * sc)
		eng_r.append(float(ed["r"]) * sc)
		eng_hp.append(0.0)
		eng_out.append(false)


func _hit_engines(p: Vector3, dmg: float) -> void:
	_init_engines()
	for i in eng_x.size():
		if bool(eng_out[i]):
			continue
		var zr: Vector2 = eng_z[i]
		if absf(p.x - float(eng_x[i])) <= float(eng_r[i]) * 1.8 and p.z >= zr.x - 1.0 and p.z <= zr.y + 1.2:
			eng_hp[i] = float(eng_hp[i]) + dmg * 1.5
			if float(eng_hp[i]) >= 0.8 or (float(eng_hp[i]) >= 0.35 and randf() < 0.18):
				_engine_fail(i, true)


func _engine_fail(i: int, show_fx: bool) -> void:
	if bool(eng_out[i]):
		return
	eng_out[i] = true
	var left: bool = float(eng_x[i]) < 0.0
	var nm: String = "PORT" if left else "STARBOARD"
	if eng_x.size() > 2:
		nm = "%s %s" % [("OUTER" if absf(float(eng_x[i])) > 4.0 else "INNER"), nm]
	var all_out: bool = engines_out_frac() >= 1.0
	_say("%s ENGINE OUT%s" % [nm, " - ALL ENGINES GONE" if all_out else " - FEATHERING"])
	if show_fx and aircraft.is_inside_tree():
		var zr: Vector2 = eng_z[i]
		var burning: bool = randf() < 0.3
		var em: Object = FX.trail(aircraft, "fire" if burning else "smoke", 1.2, Vector3(float(eng_x[i]), 0.1, zr.y))
		if em != null:
			_eng_fx.append(em)
		FX.debris(aircraft.global_position + aircraft.global_transform.basis.x * float(eng_x[i]), 5, 0.5, 14.0, Color(0.15, 0.15, 0.14))


## Is this propeller on a dead engine?
func is_feathered(prop: Node3D) -> bool:
	if eng_out.is_empty() or prop == null:
		return false
	var x: float = (aircraft.global_transform.affine_inverse() * prop.global_position).x
	var best: int = -1
	var bd: float = 1.0e9
	for i in eng_x.size():
		var d: float = absf(x - float(eng_x[i]))
		if d < bd:
			bd = d
			best = i
	return best >= 0 and bd < 2.0 and bool(eng_out[best])


func _reset_structure() -> void:
	wing_lost = {"wing_l": 0, "wing_r": 0}
	tail_lost = false
	for i in eng_out.size():
		eng_out[i] = false
		eng_hp[i] = 0.0
	for em in _eng_fx:
		if is_instance_valid(em) and em.has_method("stop"):
			em.call("stop")
	_eng_fx.clear()
	for h in _hidden:
		if is_instance_valid(h):
			(h as Node3D).visible = true
	_hidden.clear()
	if aircraft != null and aircraft._model != null:
		for n in aircraft._model.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi != null and mi.material_override is ShaderMaterial:
				mi.set_instance_shader_parameter("cut", Vector4.ZERO)
