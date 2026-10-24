class_name GroundKit
extends RefCounted
## Shared helpers for all ground-war content: cached toon materials, primitive builders,
## terrain queries, guarded FX calls (FX autoload may not exist), enemy/aircraft lookup.

static var _mats: Dictionary = {}
static var _terrain: Node = null
static var _glow_mats: Dictionary = {}
static var shells_fired: int = 0
static var peace: bool = false          # debug: AA does not fire (--wp-peace)

const COL_OLIVE := Color(0.33, 0.38, 0.2)
const COL_GREY := Color(0.42, 0.44, 0.46)
const COL_SAND := Color(0.62, 0.55, 0.38)
const COL_CONCRETE := Color(0.58, 0.58, 0.55)
const COL_DARK := Color(0.12, 0.11, 0.1)
const COL_WOOD := Color(0.42, 0.3, 0.18)
const COL_BRICK := Color(0.55, 0.3, 0.22)
const COL_STEEL := Color(0.3, 0.33, 0.37)
const COL_ALLY_VEH := Color(0.32, 0.38, 0.22)
const COL_AXIS_VEH := Color(0.4, 0.4, 0.34)


static func has_arg(a: String) -> bool:
	return OS.get_cmdline_user_args().has(a)


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


# ------------------------------------------------------------------ materials / primitives
static func mat(color: Color, outline: bool = true, thickness: float = 0.06) -> ShaderMaterial:
	var key: String = "%s_%s_%.3f" % [color.to_html(false), str(outline), thickness]
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial = ToonUtil.make_toon(color, {"outline": outline, "outline_thickness": thickness, "rim": 0.0})
	_mats[key] = m
	return m


static func glow_mat(color: Color, alpha: float = 1.0, additive: bool = false) -> StandardMaterial3D:
	var key: String = "%s_%.2f_%s" % [color.to_html(true), alpha, str(additive)]
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mats[key] = m
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, outline: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color, outline)
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func cyl(parent: Node, top_r: float, bot_r: float, h: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, segs: int = 10, outline: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(color, outline)
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, color: Color, scale_v: Vector3 = Vector3.ONE, outline: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat(color, outline)
	mi.position = pos
	mi.scale = scale_v
	parent.add_child(mi)
	return mi


## Triangular prism (roof): width along X, length along Z, height Y, base at y=0.
static func prism_mesh(w: float, l: float, h: float) -> ArrayMesh:
	var a := Vector3(-w * 0.5, 0, -l * 0.5)
	var b := Vector3(w * 0.5, 0, -l * 0.5)
	var c := Vector3(0, h, -l * 0.5)
	var d := Vector3(-w * 0.5, 0, l * 0.5)
	var e := Vector3(w * 0.5, 0, l * 0.5)
	var f := Vector3(0, h, l * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# winding: clockwise = front in Godot
	var tris: Array = [
		[a, c, b], [d, e, f],            # gable ends
		[a, d, f], [a, f, c],            # left slope
		[b, c, f], [b, f, e],            # right slope
		[a, b, e], [a, e, d],            # underside
	]
	for t in tris:
		for v in t:
			st.add_vertex(v as Vector3)
	st.generate_normals()
	return st.commit()


## Merge parts [[Mesh, Transform3D, Material], ...] into one ArrayMesh (one surface per part).
static func combine(parts: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	for p in parts:
		var m: Mesh = p[0]
		var t: Transform3D = p[1]
		var material: Material = p[2]
		var arrays: Array = m.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			verts[i] = t * verts[i]
			nrms[i] = (t.basis * nrms[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, material)
	return out


## Bake a container of static box / cylinder props (rail and canal furniture on a scenery tile) into merged meshes:
## one surface per material instead of one MeshInstance per box - a London tile carried ~400 of them, each its own draw
## call. Small structures go in a mesh that fades at `vis_small`; big ones (viaducts, bridges, sheds over BIG metres)
## stay visible as before. Anything that is not a plain Node3D / MeshInstance3D (scripted, lights, particles) is kept.
const FLATTEN_BIG := 60.0
static func flatten(container: Node3D, vis_small: float) -> Node3D:
	var out := Node3D.new()
	out.name = container.name
	var small: Dictionary = {}    # material id -> SurfaceTool
	var big: Dictionary = {}
	for top in container.get_children():
		var t3: Node3D = top as Node3D
		if t3 == null or t3.get_script() != null or not (t3.get_class() == "Node3D" or t3.get_class() == "MeshInstance3D"):
			container.remove_child(top)
			out.add_child(top)
			continue
		var parts: Array = []
		var ok: bool = true
		var aabb := AABB()
		var first: bool = true
		var stack: Array = [[t3, t3.transform]]
		while not stack.is_empty():
			var e: Array = stack.pop_back()
			var n: Node3D = e[0]
			var xf: Transform3D = e[1]
			if n.get_script() != null or not (n.get_class() == "Node3D" or n.get_class() == "MeshInstance3D"):
				ok = false
				break
			if not n.visible:
				continue      # hidden subtree stays hidden
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi: MeshInstance3D = n
				for si in mi.mesh.get_surface_count():
					var mat: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(si)
					parts.append([mi.mesh, si, xf, mat])
				var bb: AABB = xf * mi.mesh.get_aabb()
				aabb = bb if first else aabb.merge(bb)
				first = false
			for c in n.get_children():
				var c3: Node3D = c as Node3D
				if c3 == null:
					ok = false
					break
				stack.append([c3, xf * c3.transform])
			if not ok:
				break
		if not ok:
			container.remove_child(top)
			out.add_child(top)
			continue
		var bucket: Dictionary = big if aabb.get_longest_axis_size() > FLATTEN_BIG else small
		for p in parts:
			var m: Material = p[3]
			var key: int = m.get_instance_id() if m != null else 0
			if not bucket.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(m)
				bucket[key] = st
			(bucket[key] as SurfaceTool).append_from(p[0], int(p[1]), p[2])
	for pair in [[small, vis_small], [big, 0.0]]:
		var bk: Dictionary = pair[0]
		if bk.is_empty():
			continue
		var am := ArrayMesh.new()
		for k in bk:
			(bk[k] as SurfaceTool).commit(am)
		var mi2 := MeshInstance3D.new()
		mi2.mesh = am
		if float(pair[1]) > 0.0:
			mi2.visibility_range_end = float(pair[1])
		out.add_child(mi2)
	container.free()
	return out


static func box_part(size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, outline: bool = true) -> Array:
	var bm := BoxMesh.new()
	bm.size = size
	var t := Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))), pos)
	return [bm, t, mat(color, outline)]


static func cyl_part(top_r: float, bot_r: float, h: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, segs: int = 8, outline: bool = true) -> Array:
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	var t := Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))), pos)
	return [cm, t, mat(color, outline)]


# ------------------------------------------------------------------ terrain
static func terrain() -> Node:
	if _terrain == null or not is_instance_valid(_terrain):
		var t: SceneTree = tree()
		_terrain = t.get_first_node_in_group("terrain") if t else null
	return _terrain


static func ground_y(x: float, z: float) -> float:
	var t: Node = terrain()
	if t == null:
		return 0.0
	return maxf(float(t.call("get_terrain_y", x, z)), 0.0)


static func raw_y(x: float, z: float) -> float:
	var t: Node = terrain()
	if t == null:
		return 0.0
	return float(t.call("get_terrain_y", x, z))


static func is_water(x: float, z: float) -> bool:
	return raw_y(x, z) < 0.6


## Axis (unit XZ vector) along which the water near `pos` runs - the principal direction of the water samples on a
## 13 x 13 grid within `r` (a river's course at a bridge). ZERO when there is too little water.
static func river_axis(pos: Vector3, r: float) -> Vector3:
	var pts: Array = []
	var c := Vector2.ZERO
	for i in 13:
		for j in 13:
			var q := Vector2(pos.x + (float(i) - 6.0) / 6.0 * r, pos.z + (float(j) - 6.0) / 6.0 * r)
			if is_water(q.x, q.y):
				pts.append(q)
				c += q
	if pts.size() < 6:
		return Vector3.ZERO
	c /= float(pts.size())
	var sxx: float = 0.0
	var sxz: float = 0.0
	var szz: float = 0.0
	for q2 in pts:
		var d: Vector2 = (q2 as Vector2) - c
		sxx += d.x * d.x
		sxz += d.x * d.y
		szz += d.y * d.y
	var ang: float = 0.5 * atan2(2.0 * sxz, sxx - szz)
	return Vector3(cos(ang), 0.0, sin(ang))


## Direction (unit XZ vector) toward the nearest open water within max_d, or ZERO.
static func water_dir(pos: Vector3, max_d: float = 260.0) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_d: float = INF
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		var d: Vector3 = Vector3(sin(a), 0, cos(a))
		var r: float = 20.0
		while r <= max_d:
			if is_water(pos.x + d.x * r, pos.z + d.z * r):
				if r < best_d:
					best_d = r
					best = d
				break
			r += 20.0
	return best


## Allied front line by date: longitude west of which the Allies hold the ground, at latitudes 49..53 N (linear in between).
const FRONT := [
	["1944-07-25", [-0.8, -9.0, -9.0, -9.0, -9.0]],
	["1944-08-25", [2.5, 0.5, -9.0, -9.0, -9.0]],
	["1944-09-05", [5.0, 4.7, 4.6, 4.0, 3.5]],
	["1944-09-18", [5.5, 5.5, 5.6, 5.8, 5.9]],
	["1944-10-15", [6.0, 6.0, 6.0, 5.9, 5.9]],
	["1945-02-20", [6.2, 6.3, 6.4, 6.2, 6.1]],
	["1945-03-28", [7.5, 7.2, 7.4, 7.6, 7.6]],
]


static var _lp_last: int = 0
static var _lp_on: int = -1


## Load profiling (run with --loadprof): prints the time since the previous marker.
static func lp(label: String) -> void:
	if _lp_on < 0:
		_lp_on = 1 if OS.get_cmdline_user_args().has("--loadprof") else 0
	if _lp_on == 0:
		return
	var now: int = Time.get_ticks_msec()
	print("[loadprof] %-34s +%5d ms   (t=%d ms)" % [label, now - _lp_last if _lp_last > 0 else 0, now])
	_lp_last = now


static func era_date() -> String:
	var gs: Node = tree().root.get_node_or_null("GameState") if tree() else null
	return str(gs.get("era_date")) if gs != null and "era_date" in gs else ""


static func front_lon(lat: float, date: String) -> float:
	var row: Array = []
	for f in FRONT:
		if date >= str(f[0]):
			row = f[1]
	if row.is_empty():
		return -99.0
	var u: float = clampf((lat - 49.0) / 1.0, 0.0, 3.999)
	var i: int = int(u)
	return lerpf(float(row[i]), float(row[i + 1]), u - float(i))


## Which side holds this lat/lon: "Axis" on the continent, "Allies" in England. Sea defaults by nearest.
static func side_at_latlon(lat: float, lon: float) -> String:
	var date: String = era_date()
	if date != "" and lon <= front_lon(lat, date):
		return "Allies"          # liberated ground on the continent (1944-45 front line)
	if lon >= 1.5 and not (lat > 51.45 and lon < 2.0):     # (East Anglia reaches 1.75 E)
		return "Axis"
	var keys: Array = [[-4.6, 50.0], [-1.0, 50.25], [0.0, 50.38], [0.8, 50.85], [1.2, 51.05], [1.5, 51.3]]
	var mid: float = 50.0
	if lon <= -4.6:
		mid = 50.0
	else:
		for i in range(keys.size() - 1):
			var a: Array = keys[i]
			var b: Array = keys[i + 1]
			if lon >= float(a[0]) and lon <= float(b[0]):
				var f: float = (lon - float(a[0])) / (float(b[0]) - float(a[0]))
				mid = lerpf(float(a[1]), float(b[1]), f)
	return "Allies" if lat > mid else "Axis"


static func side_at(p: Vector3) -> String:
	var ll: Vector2 = WorldCoords.world_to_latlon(p)
	return side_at_latlon(ll.x, ll.y)


static func enemy_of(team: String) -> String:
	return "Axis" if team == "Allies" else "Allies"


static func team_color(team: String) -> Color:
	return COL_ALLY_VEH if team == "Allies" else COL_AXIS_VEH


# ------------------------------------------------------------------ game state helpers
static func difficulty() -> float:
	var gs: Node = tree().root.get_node_or_null("GameState") if tree() else null
	if gs and "difficulty" in gs:
		return clampf(float(gs.get("difficulty")), 0.3, 3.0)
	return 1.0


## 0..1 style multiplier applied to AA accuracy/range (fog and storms hurt gunners).
static func visibility() -> float:
	var wm: Node = tree().root.get_node_or_null("WeatherManager") if tree() else null
	if wm and wm.has_method("get_visibility_multiplier"):
		return clampf(float(wm.call("get_visibility_multiplier")), 0.25, 1.0)
	return 1.0


static func is_night() -> bool:
	var tod: Node = tree().root.get_node_or_null("TimeOfDay") if tree() else null
	if tod == null:
		return false
	var h: float = float(tod.get("hour"))
	return h < 5.3 or h > 20.4


static func aircraft_alive(a: Node) -> bool:
	if not is_instance_valid(a) or not (a is Node3D):
		return false
	if "state" in a:
		return int(a.get("state")) == 0   # Aircraft.State.ALIVE
	return true


## Enemy aircraft (for a gun of `team`), alive, within range of pos.
static func enemy_aircraft(team: String, pos: Vector3, max_range: float) -> Array:
	var out: Array = []
	var t: SceneTree = tree()
	if t == null:
		return out
	var r2: float = max_range * max_range
	for n in t.get_nodes_in_group("aircraft"):
		if not aircraft_alive(n):
			continue
		var tm: String = str(n.get("team")) if "team" in n else "Neutral"
		if tm == team or tm == "Neutral":
			continue
		if (n as Node3D).global_position.distance_squared_to(pos) <= r2:
			out.append(n)
	return out


static func player_node() -> Node3D:
	var t: SceneTree = tree()
	if t == null:
		return null
	for n in t.get_nodes_in_group("aircraft"):
		if "player_controlled" in n and bool(n.get("player_controlled")):
			return n as Node3D
	return null


# ------------------------------------------------------------------ FX (guarded)
static func fx_node() -> Node:
	var t: SceneTree = tree()
	return t.root.get_node_or_null("FX") if t else null


## Call an FX autoload method with as many of `args` as it accepts. Returns [ok, result].
static func fx_call(method: String, args: Array) -> Array:
	var fx: Node = fx_node()
	if fx == null or not fx.has_method(method):
		return [false, null]
	var n: int = -1
	for m in fx.get_method_list():
		if m["name"] == method:
			n = (m["args"] as Array).size()
			break
	if n < 0 or n > args.size():
		if n > args.size():
			return [false, null]
		return [false, null]
	return [true, fx.callv(method, args.slice(0, n))]


static func _scene_parent() -> Node:
	var t: SceneTree = tree()
	if t == null:
		return null
	var cs: Node = t.current_scene
	return cs if cs else t.root


static func explosion(pos: Vector3, size: float = 1.0) -> void:
	var r: Array = fx_call("explosion", [pos, size * 7.0])
	if r[0]:
		return
	var parent: Node = _scene_parent()
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.65, 0.2, 0.95)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.5 * size
	var tw: Tween = mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * (6.0 + 5.0 * size), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color", Color(0.15, 0.1, 0.08, 0.0), 0.7)
	tw.chain().tween_callback(mi.queue_free)


static func flak_burst(pos: Vector3, size: float = 1.0) -> void:
	var r: Array = fx_call("flak_burst", [pos])
	if r[0]:
		return
	var parent: Node = _scene_parent()
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.1, 0.1, 0.1, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 2.0 * size
	var tw: Tween = mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 11.0 * size, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color", Color(0.25, 0.22, 0.2, 0.0), 2.2).set_delay(0.3)
	tw.chain().tween_callback(mi.queue_free)


static func sparks(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	var r: Array = fx_call("sparks", [pos, normal])
	if r[0]:
		return
	var r2: Array = fx_call("sparks", [pos])
	if r2[0]:
		return


## Subtle chimney smoke attached to `parent` at local pos; ends when the parent is freed. Returns the holder node.
static func stack_smoke(parent: Node3D, local_pos: Vector3, scale_v: float = 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.position = local_pos
	parent.add_child(holder)
	if parent.is_inside_tree():
		fx_call("stack_smoke", [holder.global_position, scale_v, holder])
	return holder


## Persistent smoke (+ optional fire) attached to `parent` at local pos. Returns the node (or null).
static func persistent_smoke(parent: Node3D, local_pos: Vector3, scale_v: float = 1.0, with_fire: bool = true) -> Node3D:
	var holder := Node3D.new()
	holder.position = local_pos
	parent.add_child(holder)
	var used_fx: bool = false
	var fxn: Node = fx_node()
	if fxn and parent.is_inside_tree():
		var pos_w: Vector3 = parent.to_global(local_pos)
		var r: Array = fx_call("smoke_column", [pos_w, scale_v * 6.0, 1.0e6])
		if not r[0]:
			r = fx_call("smoke_column", [pos_w, scale_v * 6.0])
		if r[0]:
			used_fx = true
			if with_fire:
				var f: Array = fx_call("fire", [pos_w, scale_v * 4.0, 1.0e6])
				if not f[0]:
					fx_call("fire", [pos_w, scale_v * 4.0])
			if r[1] is Node:
				(r[1] as Node).reparent(holder)
	if not used_fx:
		var p := GPUParticles3D.new()
		p.amount = 24
		p.lifetime = 5.0 * scale_v
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 12.0
		pm.initial_velocity_min = 6.0 * scale_v
		pm.initial_velocity_max = 10.0 * scale_v
		pm.gravity = Vector3(1.5, 1.0, 0.0)
		pm.scale_min = 1.5 * scale_v
		pm.scale_max = 3.2 * scale_v
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.3))
		curve.add_point(Vector2(1, 1.8))
		var ct := CurveTexture.new()
		ct.curve = curve
		pm.scale_curve = ct
		var grad := Gradient.new()
		grad.set_color(0, Color(0.9, 0.45, 0.1, 0.9) if with_fire else Color(0.25, 0.25, 0.25, 0.8))
		grad.set_color(1, Color(0.08, 0.08, 0.08, 0.0))
		grad.add_point(0.15, Color(0.12, 0.11, 0.1, 0.85))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		p.process_material = pm
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = glow_mat(Color(1, 1, 1), 1.0)
		var vm := StandardMaterial3D.new()
		vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vm.vertex_color_use_as_albedo = true
		vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.material = vm
		p.draw_pass_1 = sm
		holder.add_child(p)
		p.emitting = true
		if with_fire and scale_v >= 1.4:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.55, 0.2)
			l.light_energy = 1.5
			l.omni_range = 40.0 * scale_v
			l.shadow_enabled = false
			l.position = Vector3(0, 2, 0)
			holder.add_child(l)
	return holder
