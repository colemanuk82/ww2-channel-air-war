class_name DamRunMode
extends ModeBase
## Dam Busters sortie: one mission per campaign day (see DamCampaign). Kinds:
##   "low"   fly through three rings over the Channel at 60 ft or less
##   "skip"  drop the bouncing bomb on flat water: it must skip at least SKIP_MIN times before it sinks
##   "range" the same bomb, but it must sink within RANGE_M of the release marker (release timing)
##   "dam"   breach the dam wall (must_breach). With must_breach false (Sorpe) the bomb must detonate
##           within DIVERSION_M of the wall instead.
## The sortie ends when the aircraft lands (home safe). The task has to be done before landing counts.

const SKIP_MIN: int = 4
const RANGE_M: float = 120.0
const RING_RADIUS: float = 34.0        # ring radius (world units): spans ~2 m to ~38 m above the water
const RING_CENTRE_Y: float = 40.0      # ring centre height (world units = 20 m, the middle of the 60 ft band)
const RING_TUBE: float = 3.2           # tube thickness (world units) - thick enough to read from 3 km
const RING_PASS_M: float = 52.0        # how close (horizontally) the aircraft must come to a ring's centre
const RING_NEXT := Color(1.0, 0.32, 0.04)     # the ring to fly through next: vivid signal orange (reads against pale haze AND dark sea)
const RING_LATER := Color(1.0, 0.78, 0.15)    # the ring after that: yellow
const RING_DONE := Color(0.35, 1.0, 0.45)     # passed: flashes green, then fades away
const LOW_ALT_M: float = 40.0          # "60 ft or less" (18 m), with some allowance
const DIVERSION_M: float = 160.0
const PRACTICE_HP: float = 120.0    # a must-breach wall: one bomb (140 damage) breaches it

var start_airborne: bool = true
var kind: String = "dam"
var dam_id: String = "moehne"
var practice: bool = false
var must_breach: bool = true
var title: String = "Dam Busters"
var has_marker: bool = false
var marker: Vector2 = Vector2.ZERO     # world XZ of the release marker
var rings: Array = []                  # world XZ centres of the "low" rings
var _ring_seen: Array = []
var _ring_dots: Array = []           # minimap dots, one per ring (freed once the ring is passed)
var _rings_done: int = 0
var _ring_nodes: Array = []          # one Node3D per ring (ring, halo, beacon posts, buoy)
var _ring_warn_t: float = -10.0
var _ring_fade: Array = []           # seconds since the ring was passed (-1 = not passed)
var _bomb_serial: int = 0
var _bomb_live: bool = false
var _bomb_done: bool = false
var _bomb_ok: bool = false
var _skips: int = 0
var _last_pos: Vector3 = Vector3.ZERO
var _dam_pos: Vector3 = Vector3.ZERO
var _wall: Node = null
var breached: bool = false
var _landed: bool = false
var _ended: bool = false
var _visuals: Array = []
var _skip_called: int = 0
var _high_warned: bool = false
var _autodrop: bool = false	 # debug: release the bomb automatically (--autodrop, for recording)
var _auto_fired: bool = false
# release sequence (dam runs): 0 normal, 1 bomb in flight (aircraft frozen, bomb cam), 2 breach and flood, 3 bomb missed
const CINE_FLOOD_S: float = 9.0
const CINE_MISS_S: float = 3.0
var _cine: int = 0
var _cine_t: float = 0.0
var _cine_boom: int = 0
var _flood_cam: Camera3D = null
var _prev_cam: Camera3D = null
var _home: Vector3 = Vector3.ZERO	  # the start airfield: the sortie completes when the aircraft gets back here
var _have_home: bool = false
const HOME_RADIUS: float = 1500.0


func configure(cfg: Dictionary) -> void:
	kind = str(cfg.get("kind", "dam"))
	dam_id = str(cfg.get("dam", "moehne"))
	practice = bool(cfg.get("practice", false))
	must_breach = bool(cfg.get("must_breach", true))
	title = str(cfg.get("title", "Dam Busters"))
	if cfg.has("marker"):
		var m: Array = cfg["marker"]
		var mp: Vector3 = WorldCoords.latlon_to_world(float(m[0]), float(m[1]))
		marker = Vector2(mp.x, mp.z)
		has_marker = true
	for r in cfg.get("rings", []):
		var rp: Vector3 = WorldCoords.latlon_to_world(float(r[0]), float(r[1]))
		rings.append(Vector2(rp.x, rp.z))


func start() -> void:
	super.start()
	elapsed = 0.0
	_autodrop = OS.get_cmdline_user_args().has("--autodrop")
	if kind != "low" and player is Aircraft:
		player.set_meta("upkeep", true)        # the aircraft drops a bouncing bomb (WeaponWorld.drop_bomb)
		player.bombs = 1
		player.weapon_mode = 2
		player.weapon_bombs = true
	for i in rings.size():
		_ring_seen.append(false)
		_ring_fade.append(-1.0)
		_ring_nodes.append(_make_ring(i))
		_ring_dots.append(_add_nav_dot(Vector3(rings[i].x, 0.0, rings[i].y)))
	_style_rings()
	if has_marker:
		_add_visual(Vector3(marker.x, 1.0, marker.y), RANGE_M, false, Color(1.0, 0.9, 0.35, 0.6))
		_add_nav_dot(Vector3(marker.x, 0.0, marker.y))
	if kind != "low":
		_setup_dam()
		if kind == "dam":
			_add_nav_dot(_dam_pos)
	var pl: Aircraft = player as Aircraft
	if pl != null:
		pl.destroyed.connect(_on_player_down)
	_find_home()
	radio_call("dam_start_1", 2.0)
	objective_updated.emit(_objective_text())


func stop() -> void:
	_cine_end()
	Weapons.reservoirs.clear()
	for v in _visuals:
		if is_instance_valid(v):
			(v as Node).queue_free()
	_visuals.clear()
	super.stop()


func _setup_dam() -> void:
	var pop: WorldPopulator = WorldPopulator.instance
	if pop == null:
		push_warning("DamRunMode: no world populator")
		return
	pop.reset_dam(dam_id)
	pop.pin_site("dam_" + dam_id)
	_wall = pop.dam_wall(dam_id)
	if _wall == null:
		push_warning("DamRunMode: dam %s not built" % dam_id)
		return
	_dam_pos = _wall.global_position
	if must_breach:
		_wall.max_health = PRACTICE_HP
		_wall.health = PRACTICE_HP
	_wall.destroyed.connect(_on_wall_destroyed)
	_register_reservoir()


## Steering point for the HUD: the next ring, the release or dam target, then the start airfield.
func nav_point() -> Variant:
	if kind == "low":
		for i in mini(rings.size(), _ring_seen.size()):
			if not _ring_seen[i]:
				return Vector3(rings[i].x, 0.0, rings[i].y)
	elif kind == "dam":
		if not breached and not _bomb_done:
			return _dam_pos
	elif not _bomb_done:
		return Vector3(marker.x, 0.0, marker.y)
	return _home if _have_home else null


## A minimap dot at p. The HUD drops it when the node is freed.
func _add_nav_dot(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	if hud != null:
		AIFactory.add_marker(hud, n, Color(0.55, 0.92, 1.0))
	return n


func _add_visual(p: Vector3, radius: float, vertical: bool, col: Color) -> void:
	# A wide, fog-free band (it was a thin 8% sliver that vanished into the sea haze) plus a tall light post at the
	# centre so the release marker can be found from a long way out.
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	var tube: float = maxf(radius * 0.07, 4.0)
	tm.inner_radius = radius - tube
	tm.outer_radius = radius + tube
	tm.rings = 64
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = _glow_mat(Color(col, 1.0), 0.9)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vertical:
		mi.rotation.x = deg_to_rad(90.0)
	mi.position = p
	world.add_child(mi)
	_visuals.append(mi)
	if not vertical:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.5
		cm.bottom_radius = 2.5
		cm.height = 900.0
		post.mesh = cm
		post.material_override = _glow_mat(Color(col, 1.0), 0.45, true)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post.position = p + Vector3(0.0, 450.0, 0.0)
		world.add_child(post)
		_visuals.append(post)


## The course direction at ring i: from the previous ring (or toward the next one for the first ring), so every
## ring faces the way the player arrives. (They used to all face north-south, so a run flown east saw them edge-on.)
func _ring_dir(i: int) -> Vector3:
	var d: Vector2 = Vector2.ZERO
	if i > 0:
		d = rings[i] - rings[i - 1]
	elif rings.size() > 1:
		d = rings[1] - rings[0]
	elif player is Node3D:
		var pp: Vector3 = (player as Node3D).global_position
		d = rings[i] - Vector2(pp.x, pp.z)
	if d.length() < 1.0:
		d = Vector2(0.0, -1.0)
	d = d.normalized()
	return Vector3(d.x, 0.0, d.y)


## One "low" ring: a thick glowing torus standing on the water at 60 ft, a soft halo round it, two tall light
## posts either side (seen from many km away, like goal posts showing where the gap is) and a buoy on the water.
## Unshaded and fog-free so haze, sun glare or a dark sea never wash it out.
func _make_ring(i: int) -> Node3D:
	var root := Node3D.new()
	world.add_child(root)
	var c: Vector2 = rings[i]
	var dir: Vector3 = _ring_dir(i)
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	root.global_transform = Transform3D(Basis(side, Vector3.UP, -dir), Vector3(c.x, RING_CENTRE_Y, c.y))
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = RING_RADIUS - RING_TUBE
	tm.outer_radius = RING_RADIUS + RING_TUBE
	tm.rings = 48
	tm.ring_segments = 12
	ring.mesh = tm
	ring.rotation.x = deg_to_rad(90.0)      # torus axis along the course
	ring.material_override = _glow_mat(RING_NEXT, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var hm := TorusMesh.new()
	hm.inner_radius = RING_RADIUS - RING_TUBE * 3.0
	hm.outer_radius = RING_RADIUS + RING_TUBE * 3.0
	hm.rings = 48
	hm.ring_segments = 8
	halo.mesh = hm
	halo.rotation.x = deg_to_rad(90.0)
	halo.material_override = _glow_mat(RING_NEXT, 0.3)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	for sgn in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "Post"
		var cm := CylinderMesh.new()
		cm.top_radius = 2.5
		cm.bottom_radius = 4.0
		cm.height = 900.0
		cm.radial_segments = 8
		post.mesh = cm
		post.position = Vector3(sgn * (RING_RADIUS + 12.0), 450.0 - RING_CENTRE_Y, 0.0)
		post.material_override = _glow_mat(RING_NEXT, 0.8)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(post)
	var buoy := MeshInstance3D.new()
	buoy.name = "Buoy"
	var sm := SphereMesh.new()
	sm.radius = 4.0
	sm.height = 6.0
	buoy.mesh = sm
	buoy.position = Vector3(0.0, 1.5 - RING_CENTRE_Y, 0.0)
	buoy.material_override = _glow_mat(RING_NEXT, 1.0)
	root.add_child(buoy)
	_visuals.append(root)
	return root


func _glow_mat(col: Color, alpha: float, additive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, alpha)
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## Colour the rings: the next one signal orange, the one after yellow, passed ones green.
func _style_rings() -> void:
	var next_i: int = _ring_seen.find(false)
	for i in _ring_nodes.size():
		if not is_instance_valid(_ring_nodes[i]) or _ring_seen[i]:
			continue
		var root: Node3D = _ring_nodes[i]
		var col: Color = RING_NEXT if i == next_i else RING_LATER
		for ch in root.get_children():
			var mi := ch as MeshInstance3D
			if mi == null:
				continue
			var m := mi.material_override as StandardMaterial3D
			m.albedo_color = Color(col, m.albedo_color.a)
		root.visible = i <= next_i + 1      # only the next two rings show, so the course reads clearly


## Pulse the next ring (and its halo) so it catches the eye; fade out rings already flown through.
func _animate_rings(delta: float) -> void:
	var next_i: int = _ring_seen.find(false)
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 4.0)
	for i in _ring_nodes.size():
		if not is_instance_valid(_ring_nodes[i]):
			continue
		var root: Node3D = _ring_nodes[i]
		if _ring_seen[i]:
			_ring_fade[i] += delta
			var f: float = clampf(1.0 - _ring_fade[i] / 1.5, 0.0, 1.0)
			root.scale = Vector3.ONE * (1.0 + 0.4 * (1.0 - f))
			for ch in root.get_children():
				var mi := ch as MeshInstance3D
				if mi != null:
					var m := mi.material_override as StandardMaterial3D
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.albedo_color = Color(RING_DONE, f * (0.9 if ch.name == "Ring" else 0.3))
			if f <= 0.0:
				root.queue_free()
		elif i == next_i:
			var halo := root.get_node_or_null("Halo") as MeshInstance3D
			if halo != null:
				halo.scale = Vector3.ONE * (1.0 + 0.08 * pulse)
				(halo.material_override as StandardMaterial3D).albedo_color.a = 0.15 + 0.25 * pulse


## Spotlight altimeter, as fitted to 617 Squadron's Lancasters: one lamp in the nose and one behind the bomb bay,
## angled so their spots meet on the water at exactly 60 ft. Two light spots on the surface slide together as
## the aircraft comes down and touch at 60 ft (they turn green); too high they are apart, too low they cross over.
const SPOT_BASE: float = 9.0        # half the lamp spacing along the fuselage (world units)
const SPOT_TARGET_M: float = 18.3   # 60 ft
var _spots: Array = []
var _spot_beams: Array = []


func _ensure_spots() -> void:
	if not _spots.is_empty():
		return
	for i in 2:
		var spot := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 4.5
		cm.bottom_radius = 4.5
		cm.height = 0.2
		spot.mesh = cm
		spot.material_override = _glow_mat(Color(1.0, 0.97, 0.8), 0.85, true)
		spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(spot)
		_visuals.append(spot)
		_spots.append(spot)
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.25
		bm.bottom_radius = 2.0
		bm.height = 1.0
		beam.mesh = bm
		beam.material_override = _glow_mat(Color(1.0, 0.95, 0.75), 0.12, true)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(beam)
		_visuals.append(beam)
		_spot_beams.append(beam)


func _update_spots(pl: Aircraft) -> void:
	var agl: float = pl.altitude_agl
	var show: bool = not pl.on_ground and agl > 0.5 and agl / WorldCoords.VERTICAL_SCALE < 120.0 and _cine == 0
	if not show:
		for n in _spots + _spot_beams:
			(n as Node3D).visible = false
		return
	_ensure_spots()
	var fwd: Vector3 = pl.get_forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var water_y: float = pl.global_position.y - agl + 0.4
	var h: float = SPOT_TARGET_M * WorldCoords.VERTICAL_SCALE
	var on: bool = absf(agl / WorldCoords.VERTICAL_SCALE - SPOT_TARGET_M) < 2.5
	var col: Color = Color(0.4, 1.0, 0.5) if on else Color(1.0, 0.97, 0.8)
	for i in 2:
		var sgn: float = 1.0 if i == 0 else -1.0
		var lamp: Vector3 = pl.global_position + fwd * (sgn * SPOT_BASE) + Vector3.DOWN * 1.5
		# each lamp aims inward so the beams cross the fuselage line exactly h below the lamps
		var hit: Vector3 = lamp + fwd * (-sgn * SPOT_BASE * agl / h)
		hit.y = water_y
		var spot: MeshInstance3D = _spots[i]
		spot.visible = true
		spot.global_position = hit
		(spot.material_override as StandardMaterial3D).albedo_color = Color(col, 0.85)
		var beam: MeshInstance3D = _spot_beams[i]
		var d: Vector3 = hit - lamp
		var ln: float = d.length()
		beam.visible = ln > 1.0
		if beam.visible:
			var up: Vector3 = -d / ln
			var x: Vector3 = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
			beam.global_transform = Transform3D(Basis(x, up * ln, x.cross(up)), lamp + d * 0.5)


func _objective_text() -> String:
	match kind:
		"low":
			return "Fly through the rings at 60 ft or less (%d of %d). Then land at a friendly airfield." % [_rings_done, rings.size()]
		"skip":
			if _bomb_done:
				return "Skips: %d. Now land at a friendly airfield." % _skips
			return "Drop the bomb on the marked water. It must skip at least %d times." % SKIP_MIN
		"range":
			if _bomb_done:
				return "Now land at a friendly airfield."
			return "Release the bomb so it sinks within %d m of the ring." % int(RANGE_M)
		_:
			if breached:
				return "The wall has gone. Land at a friendly airfield."
			if _bomb_done:
				return "Now land at a friendly airfield."
			if must_breach:
				return "Fly low over the reservoir, drop the bomb against the wall and breach the dam."
			return "Bomb the dam wall. Diversion: the bomb must detonate near the wall."


func _process(delta: float) -> void:
	if not running or _ended or not (player is Aircraft):
		return
	elapsed += delta
	_cine_update(delta)
	var pl: Aircraft = player as Aircraft
	if kind == "low":
		_check_rings(pl)
		_animate_rings(delta)
	if kind == "low" and not _high_warned and elapsed > 8.0 and pl.get_altitude_m() > LOW_ALT_M * 2.0:
		_high_warned = true
		radio_call("dam_high_1")
	if _autodrop and not _auto_fired and kind != "low" and pl.bombs > 0:
		# debug release: drop when the bomb's own fall (same gravity as WeaponWorld) carries it onto the target
		var tgt3: Vector3 = _dam_pos if kind == "dam" else Vector3(marker.x, 0.0, marker.y)
		var fall: float = sqrt(2.0 * maxf(pl.global_position.y - tgt3.y, 0.0) / Weapons.BOMB_GRAVITY)
		var hspeed: float = Vector2(pl.velocity.x, pl.velocity.z).length()
		var dd: float = Vector2(pl.global_position.x, pl.global_position.z).distance_to(Vector2(tgt3.x, tgt3.z))
		if dd <= hspeed * fall:
			_auto_fired = true
			pl.bomb_requested.emit(pl)
	_update_spots(pl)
	_check_home(pl)
	var sv: Dictionary = Weapons.skip_bomb_view()
	var serial: int = int(sv["serial"])
	if serial != _bomb_serial and serial > 0 and bool(sv["live"]):
		_bomb_serial = serial
		_bomb_live = true
		_bomb_done = false
		_skips = 0
		_skip_called = 0
		radio_call_any("dam_bomb", 2)
		if kind == "dam":
			_cine_begin()
		objective_updated.emit("Bomb away. Watch it skip.")
	if _bomb_live:
		if bool(sv["live"]):
			_skips = int(sv["skips"])
			if _skips > _skip_called:
				_skip_called = _skips
				if _skips == 1:
					radio_call_any("dam_skip", 2)
				elif _skips == SKIP_MIN:
					radio_call("dam_skip_3")
			_last_pos = sv["pos"]
		else:
			_bomb_live = false
			_bomb_done = true
			_judge_bomb()
			_bomb_radio()
			objective_updated.emit(_objective_text())


func _check_rings(pl: Aircraft) -> void:
	var p: Vector3 = pl.global_position
	var alt: float = pl.get_altitude_m()
	for i in rings.size():
		if _ring_seen[i]:
			continue
		var near: bool = Vector2(p.x, p.z).distance_to(rings[i]) <= RING_PASS_M
		if near and alt > LOW_ALT_M and hud != null and hud.has_method("show_message") and elapsed - _ring_warn_t > 3.0:
			_ring_warn_t = elapsed
			hud.call("show_message", "TOO HIGH - ring not counted. Come round below 60 ft (%d m)." % int(LOW_ALT_M), 3.0)
		if near and alt <= LOW_ALT_M and alt >= 2.0:
			_ring_seen[i] = true
			if is_instance_valid(_ring_dots[i]):
				_ring_dots[i].queue_free()
			_rings_done += 1
			_ring_fade[i] = 0.0
			_style_rings()
			radio_call("dam_ring_%d" % _rings_done)
			objective_updated.emit(_objective_text())


func _judge_bomb() -> void:
	var at: Vector2 = Vector2(_last_pos.x, _last_pos.z)
	match kind:
		"skip":
			_bomb_ok = _skips >= SKIP_MIN
		"range":
			_bomb_ok = at.distance_to(marker) <= RANGE_M
		"dam":
			if must_breach:
				_bomb_ok = breached
			else:
				_bomb_ok = Vector2(_dam_pos.x, _dam_pos.z).distance_to(at) <= DIVERSION_M
		_:
			_bomb_ok = true


func _bomb_radio() -> void:
	if kind == "skip" or kind == "range":
		radio_call("dam_sink_1" if _bomb_ok else "dam_wide_1", 1.0)
	elif kind == "dam" and not must_breach:
		radio_call("dam_detonate_1" if _bomb_ok else "dam_wide_1", 1.0)


func _on_wall_destroyed(_n: Node, _k: Node) -> void:
	breached = true
	radio_call_any("dam_breach", 2, 0.5)
	objective_updated.emit(_objective_text())


func _on_player_down(_a: Node, _k: Node) -> void:
	if _ended:
		return
	radio_call("dam_down_1")
	_end(false)


func _end(success: bool) -> void:
	if _ended:
		return
	_ended = true
	var extra: Dictionary = {
		"mission": title, "kind": kind, "skips": _skips, "breached": breached, "rings": _rings_done,
		"home": _landed, "score": 1000 if success else 0,
	}
	finish(success, extra)


## Release sequence: freeze the aircraft where the bomb is let go, follow the bomb, then on a breach show the
## explosions and the flood from downstream, and hand control back to the player.
func _cine_set(s: int) -> void:
	_cine = s
	_cine_t = 0.0
	_cine_boom = 0


func _cine_begin() -> void:
	_cine_set(1)
	if player is Node:
		(player as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(player as Node).set_process(false)
		(player as Node).set_physics_process(false)


func _cine_update(delta: float) -> void:
	if _cine == 0:
		return
	_cine_t += delta
	if _cine == 1:
		if breached:
			_cine_enter_flood()
		elif _bomb_done and _cine_t > 1.0:
			_cine_set(3)
	elif _cine == 2:
		var booms: Array = [0.0, 0.6, 1.4, 2.4]
		if _cine_boom < booms.size() and _cine_t >= float(booms[_cine_boom]):
			_breach_boom(_cine_boom)
			_cine_boom += 1
		if _cine_t >= CINE_FLOOD_S:
			_cine_end()
	elif _cine == 3:
		if _cine_t >= CINE_MISS_S:
			_cine_end()


func _breach_boom(i: int) -> void:
	var xs: Array = [-30.0, 26.0, -8.0, 44.0]
	var p: Vector3 = _dam_pos + Vector3(float(xs[i]), 10.0 + float(i) * 6.0, -6.0)
	FX.explosion(p, 22.0 + float(i) * 6.0)


func _cine_enter_flood() -> void:
	_cine_set(2)
	_prev_cam = get_viewport().get_camera_3d()
	_flood_cam = Camera3D.new()
	_flood_cam.fov = 55.0
	world.add_child(_flood_cam)
	var fwd: Vector3 = Vector3(0.0, 0.0, -1.0)
	if _wall != null and is_instance_valid(_wall):
		fwd = -(_wall as Node3D).global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var cam_p: Vector3 = _dam_pos + fwd * 170.0
	cam_p.y = GroundKit.ground_y(cam_p.x, cam_p.z) + 48.0
	_flood_cam.global_position = cam_p
	_flood_cam.look_at(_dam_pos + Vector3.UP * 14.0, Vector3.UP)
	_flood_cam.make_current()


func _cine_end() -> void:
	if _cine == 0 and _flood_cam == null and _prev_cam == null:
		return
	_cine = 0
	if _flood_cam != null and is_instance_valid(_flood_cam):
		_flood_cam.queue_free()
	_flood_cam = null
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	_prev_cam = null
	if player is Node:
		(player as Node).process_mode = Node.PROCESS_MODE_INHERIT
		(player as Node).set_process(true)
		(player as Node).set_physics_process(true)


## The start airfield, as bombing_mode resolves it.
func _find_home() -> void:
	var af: Airfield = null
	var id: String = GameState.start_airfield
	if world != null and "airfields" in world:
		var afs: Dictionary = world.get("airfields")
		if afs.has(id):
			af = afs[id]
	if af == null and WorldPopulator.instance != null:
		af = WorldPopulator.instance.get_airfield(id)
	if af != null:
		_home = Vector3(af.position.x, af.surface_y, af.position.z)
		_have_home = true


## Mission complete: the task is done and the aircraft is back over its airfield, low, with the gear down.
## Flying over the field is enough; touching down is not required.
func _check_home(pl: Aircraft) -> void:
	if not _have_home or _cine != 0 or _ended:
		return
	var task_done: bool = _rings_done >= rings.size() if kind == "low" else (_bomb_done and _bomb_ok)
	if not task_done or not pl.gear_down:
		return
	var dh: float = Vector2(pl.global_position.x - _home.x, pl.global_position.z - _home.z).length()
	if dh < HOME_RADIUS and (pl.on_ground or pl.altitude_agl < 220.0):
		radio_call_any("dam_home", 2)
		_end(true)


## The reservoir behind the wall, as GroundKit/DamKit build it: upstream (the wall's heading + 180), its
## radius from the record's area, its surface at the dam's ground level + 1.6. The bomb skips on it.
func _register_reservoir() -> void:
	var rec: Dictionary = DamKit._record(dam_id)
	if rec.is_empty():
		return
	var area: float = maxf(float(rec.get("reservoir_km2", 1.0)), 0.2) * 1000000.0
	var wl: float = clampf(float(rec.get("wall_len_m", 300.0)), 300.0, 460.0)
	var radius: float = clampf(sqrt(area / PI), wl * 0.7, 2200.0)
	var h: float = deg_to_rad(float(rec.get("heading_deg", 0.0)))
	var up := Vector3(-sin(h), 0.0, cos(h))
	var c: Vector3 = _dam_pos + up * (radius + 40.0)
	var y: float = -1.0   # follow the terrain (the DEM upstream sits above the dam base)
	Weapons.reservoirs.append({"c": Vector2(c.x, c.z), "r": radius * 1.05, "y": y})
