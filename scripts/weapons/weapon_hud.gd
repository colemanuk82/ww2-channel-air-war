class_name WeaponHud
extends CanvasLayer
## Player aids drawn over the 3D view: gun convergence pipper, target bracket + lead indicator,
## bombsight with predicted impact marker, plus an ammo/bomb readout added through HUD.add_widget().

const COL_GUN := Color(1.0, 0.92, 0.45, 0.9)
const COL_TGT := Color(1.0, 0.35, 0.25, 0.95)
const COL_BOMB := Color(1.0, 0.65, 0.2, 0.95)
const COL_HIT := Color(0.5, 1.0, 0.45, 0.95)

var ws: WeaponSystem
var aircraft: Aircraft

var _c: Control
var _ammo_lbl: Control
var _hud: HUD
var _target: Node3D
var _lead: Vector3 = Vector3.ZERO
var _has_lead: bool = false
var _bomb_show: bool = false
var _impact: Vector3 = Vector3.ZERO
var _on_target: bool = false
var _impact_root: Node3D
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _pulse_t: float = 0.0
var _terrain: Node


func bind(w: WeaponSystem) -> void:
	ws = w
	aircraft = w.aircraft


func _ready() -> void:
	layer = 9
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw_overlay)
	add_child(_c)


func _find_hud() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for n in scene.get_children():
		if n is HUD:
			_hud = n
			_ammo_lbl = Control.new()
			_ammo_lbl.custom_minimum_size = Vector2(160, 34)
			_ammo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ammo_lbl.draw.connect(_draw_ammo)
			_hud.add_widget(_ammo_lbl)
			return


func _process(delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	if _hud == null:
		_find_hud()
	if _ammo_lbl:
		_ammo_lbl.visible = true
		_ammo_lbl.queue_redraw()
	_c.visible = aircraft.state != Aircraft.State.DEAD
	_update_aids()
	_c.queue_redraw()
	_pulse_t += delta
	if _impact_root != null and is_instance_valid(_impact_root):
		var show: bool = _bomb_show and aircraft.state != Aircraft.State.DEAD
		_impact_root.visible = show
		if show and _ring_mat != null:
			_ring_mat.set_shader_parameter("emission_energy", 0.3 + 0.15 * sin(_pulse_t * 6.0))


## Compact weapon strip (top left): icon + count per weapon, the selected one in brass, the rest dimmed.
## Short red banner under the ammo strip (LOW AMMO / OUT OF AMMO).
func flash(text: String) -> void:
	if _hud != null and _hud.has_method("show_message"):
		_hud.call("show_message", text, 2.5)


func _draw_ammo() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var c: Control = _ammo_lbl
	var font: Font = UIKit.font(true)
	const FS: int = 20
	var items: Array = [[0, aircraft.ammo, aircraft.max_ammo()]]
	if aircraft.max_rockets() > 0:
		items.append([1, ws.rockets_left, aircraft.max_rockets()])
	if aircraft.max_bombs() > 0:
		items.append([2, aircraft.bombs, aircraft.max_bombs()])
	# a dark glass plate behind the strip, the same as the mission card above it
	var total: float = 12.0
	for it0 in items:
		total += 38.0 + font.get_string_size(str(it0[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
	c.custom_minimum_size = Vector2(total, 34.0)
	c.draw_rect(Rect2(0, 0, total, 34.0), HUD.CARD_BG)
	c.draw_rect(Rect2(0, 0, 4.0, 34.0), Color(0.93, 0.74, 0.32, 0.95))
	c.draw_rect(Rect2(0, 0, total, 34.0), Color(0.72, 0.58, 0.32, 0.30), false, 1.0)
	var x: float = 14.0
	for it in items:
		var mode: int = it[0]
		var left: int = it[1]
		var full: int = maxi(int(it[2]), 1)
		var sel: bool = aircraft.weapon_mode == mode
		var col: Color = Color(0.93, 0.74, 0.32, 1.0) if sel else Color(0.92, 0.9, 0.82, 0.72)
		if left <= 0:
			col = Color(1.0, 0.35, 0.25, 0.8)
		elif float(left) / float(full) < 0.2:
			col = Color(1.0, 0.65, 0.3, 0.9)
		var ic := Vector2(x + 9.0, 17.0)
		_weapon_icon(c, mode, ic, col)
		var t: String = str(left)
		var tw: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		c.draw_string(font, Vector2(x + 23.0, 25.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0, 0, 0, 0.8 * col.a))
		c.draw_string(font, Vector2(x + 22.0, 24.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, col)
		if sel:
			c.draw_line(Vector2(x, 30.0), Vector2(x + 24.0 + tw, 30.0), col, 2.0)
		x += 38.0 + tw


## Tiny silhouettes: 0 cartridges, 1 rocket, 2 bomb.
func _weapon_icon(c: Control, mode: int, p: Vector2, col: Color) -> void:
	var sh := Color(0, 0, 0, 0.5 * col.a)
	match mode:
		0:
			for dx in [-4.0, 0.0, 4.0]:
				var b := Rect2(p.x + dx - 1.4, p.y - 3.0, 2.8, 8.0)
				c.draw_rect(Rect2(b.position + Vector2(1, 1), b.size), sh)
				c.draw_rect(b, col)
				c.draw_colored_polygon(PackedVector2Array([Vector2(p.x + dx - 1.4, p.y - 3.0), Vector2(p.x + dx, p.y - 7.0), Vector2(p.x + dx + 1.4, p.y - 3.0)]), col)
		1:
			var body := PackedVector2Array([Vector2(p.x - 8, p.y + 1.5), Vector2(p.x + 4, p.y + 1.5), Vector2(p.x + 8, p.y), Vector2(p.x + 4, p.y - 1.5), Vector2(p.x - 8, p.y - 1.5)])
			c.draw_colored_polygon(body, col)
			c.draw_colored_polygon(PackedVector2Array([Vector2(p.x - 8, p.y - 1.5), Vector2(p.x - 10, p.y - 5), Vector2(p.x - 5, p.y - 1.5)]), col)
			c.draw_colored_polygon(PackedVector2Array([Vector2(p.x - 8, p.y + 1.5), Vector2(p.x - 10, p.y + 5), Vector2(p.x - 5, p.y + 1.5)]), col)
		_:
			c.draw_circle(p + Vector2(0, 1.5), 4.2, col)
			c.draw_colored_polygon(PackedVector2Array([Vector2(p.x - 4.1, p.y + 0.5), Vector2(p.x, p.y + 9.0), Vector2(p.x + 4.1, p.y + 0.5)]), col)
			c.draw_rect(Rect2(p.x - 3.5, p.y - 6.5, 7.0, 2.0), col)
			c.draw_line(Vector2(p.x, p.y - 4.5), Vector2(p.x, p.y - 2.0), col, 1.5)


## 3D marker on the terrain at the predicted bomb impact point.
func _ensure_impact_marker() -> void:
	if _impact_root != null:
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_impact_root = Node3D.new()
	_impact_root.name = "BombImpactMarker"
	scene.add_child(_impact_root)
	# flat crosshair (annulus + cross bars) built by hand, lies in the XZ plane
	var segs := 48
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs:
		var a0: float = float(i) / float(segs) * TAU
		var a1: float = float(i + 1) / float(segs) * TAU
		var c0 := Vector3(cos(a0), 0.0, sin(a0))
		var c1 := Vector3(cos(a1), 0.0, sin(a1))
		var base: int = verts.size()
		verts.append(c0 * 0.87)
		verts.append(c1 * 0.87)
		verts.append(c0)
		verts.append(c1)
		for _n in 4:
			norms.append(Vector3.UP)
		idx.append(base)
		idx.append(base + 1)
		idx.append(base + 2)
		idx.append(base + 1)
		idx.append(base + 3)
		idx.append(base + 2)
	# cross bars: two quads, half-length 1.2 / half-width 0.04, +Y facing
	var cross: PackedVector3Array = PackedVector3Array([
		Vector3(-0.04, 0, -1.2), Vector3(0.04, 0, 1.2), Vector3(0.04, 0, -1.2),
		Vector3(-0.04, 0, -1.2), Vector3(-0.04, 0, 1.2), Vector3(0.04, 0, 1.2),
		Vector3(-1.2, 0, -0.04), Vector3(1.2, 0, 0.04), Vector3(1.2, 0, -0.04),
		Vector3(-1.2, 0, -0.04), Vector3(-1.2, 0, 0.04), Vector3(1.2, 0, 0.04),
	])
	var xbase: int = verts.size()
	for v in cross:
		verts.append(v)
		norms.append(Vector3.UP)
	for i in 12:
		idx.append(xbase + i)
	var arr := Array()
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var ring_mesh := ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_mat = ToonUtil.make_toon(COL_BOMB, {"emission": COL_BOMB, "emission_energy": 0.35, "outline": false})
	_ring.material_override = _ring_mat
	_impact_root.add_child(_ring)
	_impact_root.visible = false


func _update_aids() -> void:
	var st: AircraftStats = aircraft.stats
	var fwd: Vector3 = aircraft.get_forward()
	var pos: Vector3 = aircraft.global_position
	# --- target + lead
	TargetIndex.ensure(get_tree())
	var best: Node3D = TargetIndex.best_in_cone(pos, fwd, aircraft.team, 5.0, 1800.0, 0.8)
	_target = best
	_has_lead = false
	if best:
		var rel_p: Vector3 = best.global_position - pos
		var tv: Variant = best.get("velocity")
		var rel_v: Vector3 = (tv as Vector3 if tv is Vector3 else Vector3.ZERO) - aircraft.velocity
		var s: float = st.gun_speed
		var a: float = rel_v.dot(rel_v) - s * s
		var b: float = 2.0 * rel_p.dot(rel_v)
		var c: float = rel_p.dot(rel_p)
		var tt: float = -1.0
		if absf(a) < 0.001:
			if absf(b) > 0.0001:
				tt = -c / b
		else:
			var disc: float = b * b - 4.0 * a * c
			if disc >= 0.0:
				var sq: float = sqrt(disc)
				var t1: float = (-b - sq) / (2.0 * a)
				var t2: float = (-b + sq) / (2.0 * a)
				tt = minf(t1, t2) if t1 > 0.0 and t2 > 0.0 else maxf(t1, t2)
		if tt > 0.0 and tt < st.gun_range / st.gun_speed:
			_lead = best.global_position + rel_v * tt   # display point: where to point the nose
			_has_lead = true
	# --- bombsight (only while the bombs weapon is selected)
	_bomb_show = aircraft.weapon_bombs and not aircraft.torpedo_load and aircraft.bombs > 0 and not aircraft.on_ground and not aircraft.bombsight_only
	if _bomb_show:
		var vel: Vector3 = aircraft.velocity
		if vel.length_squared() < 1.0:
			vel = fwd * aircraft.speed
		_impact = Weapons.predict_bomb_impact(pos - aircraft.global_transform.basis.y * 1.8, vel)
		_on_target = TargetIndex.any_near(_impact, aircraft.team, st.bomb_radius)
		_ensure_impact_marker()
		if _impact_root != null and is_instance_valid(_impact_root) and _ring != null:
			var gh: float = _terrain_height(_impact)
			_impact_root.position = Vector3(_impact.x, gh + 0.5, _impact.z)
			var r: float = clampf(st.bomb_radius * 0.22, 2.5, 12.0)      # a small mark: the ring lies flat on the ground
			_ring.scale = Vector3(r, 1.0, r)
			var col: Color = COL_HIT if _on_target else COL_BOMB
			if _ring_mat != null:
				_ring_mat.set_shader_parameter("albedo", col)
				_ring_mat.set_shader_parameter("emission_color", col)


func _screen(p: Vector3) -> Variant:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


func _draw_overlay() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var st: AircraftStats = aircraft.stats
	if aircraft.weapon_bombs and aircraft.torpedo_load:
		_draw_torpedo_sight(cam)
		return
	if aircraft.weapon_bombs:
		# Bombers with a proper bombsight only show a sight in the dedicated bombsight view (key N draws its
		# own graticule); the HUD crosshair must not appear in the chase or cockpit views.
		if aircraft.bombsight_only:
			return
		# no on-screen crosshair or impact circle: bombing aims by the small impact mark laid on the ground
		# (BombImpactMarker), nothing else
		return
	# target bracket + lead
	if _target != null and is_instance_valid(_target):
		var tp: Variant = _screen(_target.global_position)
		if tp != null:
			var t: Vector2 = tp
				# (no target box: the enemy outline already marks it; only the lead marker is drawn)
			if _has_lead and GameState.show_lead_marker:
				var lp: Variant = _screen(_lead)
				if lp != null:
					var lv: Vector2 = lp
					_c.draw_arc(lv, 9.0, 0.0, TAU, 20, COL_GUN, 2.0)
					_c.draw_circle(lv, 1.8, COL_GUN)
					_c.draw_line(t, lv, Color(COL_GUN, 0.35), 1.0)


## Torpedo sight (light, era-fitting): the drop figures (height, speed, angle) against the weapon's limits, the spot
## where a torpedo released now would enter the sea with its track, and a lead mark on the nearest enemy ship ahead
## (the torpedo's own running speed against the ship's course and speed).
func _draw_torpedo_sight(cam: Camera3D) -> void:
	var tp: GDScript = Weapons.TorpedoScript
	var tid: String = tp.type_for_model(aircraft.stats.model_id)
	if tid == "":
		tid = "mk12"
	var vel: Vector3 = aircraft.velocity
	if vel.length_squared() < 1.0:
		vel = aircraft.get_forward() * aircraft.speed
	var hs: float = Vector2(vel.x, vel.z).length()
	var alt_m: float = maxf(aircraft.global_position.y, 0.0) / WorldCoords.VERTICAL_SCALE
	var path_deg: float = rad_to_deg(atan2(vel.y / WorldCoords.VERTICAL_SCALE, maxf(hs, 0.1)))
	var roll_deg: float = rad_to_deg(aircraft.global_transform.basis.get_euler().z)
	var v: Dictionary = tp.evaluate_release(tid, alt_m, hs, path_deg, roll_deg, 40.0)
	var good: bool = bool(v["ok"])
	var col: Color = COL_HIT if (good and v["problems"].is_empty()) else (COL_BOMB if good else COL_TGT)
	var font: Font = ThemeDB.fallback_font
	var cx: float = _c.size.x * 0.5
	var y0: float = _c.size.y * 0.80
	var lim: Dictionary = tp.TYPES[tid]
	_c.draw_string(font, Vector2(cx - 150.0, y0), "TORPEDO  %s   ALT %d m (max %d)   SPD %d km/h (max %d)" % [
		String(v["status"]), int(alt_m), int(lim["max_alt"]), int(hs * 3.6), int(float(lim["max_speed"]) * 3.6)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
	# entry point + track
	var ent: Dictionary = tp.predict_entry(aircraft.global_position - aircraft.global_transform.basis.y * 1.5, vel)
	var ep: Vector3 = ent["pos"]
	var sp: Variant = _screen(ep)
	if sp != null:
		var p: Vector2 = sp
		_c.draw_arc(p, 9.0, 0.0, TAU, 20, col, 2.0)
		_c.draw_circle(p, 1.8, col)
		var hd := Vector3(vel.x, 0.0, vel.z).normalized()
		var far: Variant = _screen(ep + hd * 700.0)
		if far != null:
			_c.draw_line(p, far, Color(col, 0.55), 1.5)
	# lead mark on the nearest enemy ship that lies ahead
	var best: Node3D = null
	var best_d: float = 3500.0
	var fwd: Vector3 = aircraft.get_forward()
	for n in get_tree().get_nodes_in_group("ship"):
		var sh := n as Node3D
		if sh == null or bool(sh.get("is_dead")) or String(sh.get("team")) == aircraft.team:
			continue
		var rel: Vector3 = sh.global_position - aircraft.global_position
		var d: float = rel.length()
		if d < best_d and rel.normalized().dot(fwd) > 0.5:
			best_d = d
			best = sh
	if best != null:
		var sv: Vector3 = -best.global_transform.basis.z.normalized() * float(best.get("speed")) if float(best.get("speed")) > 0.0 else Vector3.ZERO
		var lead: Vector3 = tp.lead_point(tid, ep, best.global_position, sv, float(ent["t"]))
		var bp: Variant = _screen(best.global_position)
		if bp != null:
			_c.draw_rect(Rect2((bp as Vector2) - Vector2(11, 11), Vector2(22, 22)), Color(COL_TGT, 0.8), false, 1.5)
		if lead != Vector3.ZERO:
			var lp: Variant = _screen(Vector3(lead.x, 0.0, lead.z))
			if lp != null:
				var l: Vector2 = lp
				_c.draw_colored_polygon(PackedVector2Array([l + Vector2(0, -10), l + Vector2(10, 0), l + Vector2(0, 10), l + Vector2(-10, 0)]), Color(COL_GUN, 0.35))
				_c.draw_polyline(PackedVector2Array([l + Vector2(0, -10), l + Vector2(10, 0), l + Vector2(0, 10), l + Vector2(-10, 0), l + Vector2(0, -10)]), COL_GUN, 2.0)
				_c.draw_string(font, l + Vector2(14.0, 5.0), "AIM  %d m" % int(best_d), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_GUN)
		else:
			_c.draw_string(font, Vector2(cx - 150.0, y0 + 20.0), "NO INTERCEPT: close the range", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_BOMB)


## Fixed bombsight graticule (vertical + horizontal hairs with ticks) at the view centre.
func _draw_bomb_reticle() -> void:
	var c: Vector2 = _c.size * 0.5
	var col: Color = Color(COL_BOMB, 0.9)
	_c.draw_line(c + Vector2(0, -90), c + Vector2(0, 40), col, 1.5)
	_c.draw_line(c + Vector2(-70, 0), c + Vector2(70, 0), col, 1.5)
	for i in 5:
		var dx: float = (float(i) - 2.0) * 18.0
		var h: float = 20.0 if i % 2 == 0 else 10.0
		_c.draw_line(c + Vector2(dx, -h), c + Vector2(dx, 0), col, 1.0)
	for i in 4:
		var dy: float = -60.0 + float(i) * 22.0
		_c.draw_line(c + Vector2(-9, dy), c + Vector2(9, dy), col, 1.0)
	_c.draw_arc(c, 3.0, 0.0, TAU, 12, col, 1.5)


## Predicted-impact bombsight reticle.
func _draw_bombsight(cam: Camera3D, st: AircraftStats) -> void:
	var ip: Variant = _screen(_impact)
	if ip == null:
		return
	var p: Vector2 = ip
	var col: Color = COL_HIT if _on_target else COL_BOMB
	var edge: Variant = _screen(_impact + cam.global_transform.basis.x * st.bomb_radius)
	var r: float = 14.0
	if edge != null:
		r = clampf((edge as Vector2).distance_to(p), 8.0, 160.0)
	_c.draw_arc(p, r, 0.0, TAU, 32, col, 2.0)
	_c.draw_line(p + Vector2(-r * 0.6, 0), p + Vector2(r * 0.6, 0), col, 1.5)
	_c.draw_line(p + Vector2(0, -r * 0.6), p + Vector2(0, r * 0.6), col, 1.5)
	var font: Font = ThemeDB.fallback_font
	var dist_m: float = aircraft.global_position.distance_to(_impact)
	_c.draw_string(font, p + Vector2(r + 6.0, 5.0), "%s  %d m" % ["ON TARGET" if _on_target else "IMPACT", int(dist_m)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


## Ground height under a world position (the marker rides the terrain).
func _terrain_height(p: Vector3) -> float:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")
	if _terrain != null:
		return _terrain.call("get_height_at", p)
	return p.y
