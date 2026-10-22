class_name DamKit
extends RefCounted
## 1940s dam scenery for the Dam Busters targets (P3). The destructible masonry wall itself is a
## GroundStructure("dam") (with a breached wreck state); this kit builds everything AROUND it: the
## reservoir that reads as water, the hydro-electric powerhouse below the wall, the spillway apron, the
## anti-torpedo net boom the RAF had to clear, and the valley shoulders the wall closes.
## All procedural low-poly toon from GroundKit primitives - no photo textures, no new assets.
##
##   var n: Node3D = DamKit.build(id)          # id from data/dams_1940.json; node sits at world ORIGIN
##
## The site's lat/lon is looked up (cached) so callers only pass the id. The dam wall runs along local X
## (front = local -Z downstream); the reservoir is on local +Z (upstream of the wall).

static var _index: Dictionary = {}


## id -> record from data/dams_1940.json (cached), or {} if unknown.
static func _record(id: String) -> Dictionary:
	if _index.is_empty():
		var f: FileAccess = FileAccess.open("res://data/dams_1940.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f = null
			if d is Dictionary:
				for e in (d as Dictionary).get("dams", []):
					var ed: Dictionary = e
					_index[str(ed.get("id", ""))] = ed
	return _index.get(id, {})


## Build the dam scenery for `id`. Returns a container at the world origin (empty if the id is unknown).
static func build(id: String) -> Node3D:
	var container := Node3D.new()
	var rec: Dictionary = _record(id)
	if rec.is_empty():
		return container
	var pos: Vector3 = WorldCoords.latlon_to_world(float(rec.get("lat", 0.0)), float(rec.get("lon", 0.0)))
	var heading: float = float(rec.get("heading_deg", 0.0))
	var wall_len: float = float(rec.get("wall_len_m", 300.0))
	var wall_h: float = float(rec.get("wall_h_m", 40.0))
	var area_km2: float = float(rec.get("reservoir_km2", 1.0))
	var seed_v: int = hash(id)
	var base_y: float = GroundKit.ground_y(pos.x, pos.z)
	var span: float = clampf(wall_len, 300.0, 460.0)      # match GroundStructure("dam")'s fixed wall span
	var root := Node3D.new()
	root.position = Vector3(pos.x, base_y, pos.z)
	root.rotation.y = -deg_to_rad(heading)
	container.add_child(root)
	_reservoir(root, area_km2, span, seed_v)
	_powerhouse(root, span, wall_h)
	_valley_shoulders(root, span, wall_h)
	_net_boom(root, span)
	return container


## The reservoir: a low-poly irregular lake surface just above the local ground (in the real DEM the lake
## already sits at the dam's elevation), plus a darker shore band so the waterline reads from the air.
## The area is taken from the record's reservoir_km2 -> a working radius for the water body.
static func _reservoir(root: Node3D, area_km2: float, wall_len: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 17
	var area_m2: float = maxf(area_km2, 0.2) * 1000000.0
	var radius: float = clampf(sqrt(area_m2 / PI), wall_len * 0.7, 2200.0)
	var n: int = 16
	var cy: float = 1.6
	var cz: float = radius + 40.0                                    # the lake lies entirely upstream (local +Z)
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var r1: float = radius * rng.randf_range(0.78, 1.15)
		var b: float = TAU * float((i + 1) % n) / float(n)
		var r2: float = radius * rng.randf_range(0.78, 1.15)
		water.add_vertex(Vector3(0.0, cy, cz))
		water.add_vertex(Vector3(cos(a) * r1, cy, cz + sin(a) * r1))
		water.add_vertex(Vector3(cos(b) * r2, cy, cz + sin(b) * r2))
	water.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = water.commit()
	# the sea's water shader in lake mode: lit like water, reflects the sky, and the moon lays a path across it
	# on a night raid (it was a flat unshaded colour)
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader") as Shader
	wm.set_shader_parameter("lake_mode", 1.0)
	wm.render_priority = -100        # under spray / plumes (see WaterPlane)
	wm.set_shader_parameter("deep_color", Color(0.035, 0.085, 0.10))
	wm.set_shader_parameter("mid_color", Color(0.05, 0.11, 0.12))
	mi.material_override = wm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# a darker shore / silt band just outside the waterline
	var band := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 1.06
	cyl.bottom_radius = radius * 1.06
	cyl.height = 0.3
	cyl.radial_segments = n
	cyl.rings = 1
	band.mesh = cyl
	var band_mat: Material = GroundKit.glow_mat(Color(0.20, 0.20, 0.15), 0.45, false).duplicate()   # own copy: glow_mat is cached
	band_mat.render_priority = -120       # under the lake water (which draws early, at -100)
	band.material_override = band_mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.position = Vector3(0.0, cy - 0.2, cz)
	root.add_child(band)


## The powerhouse below the wall (downstream, local -Z): a turbine hall, two chimneys and a tailrace.
static func _powerhouse(root: Node3D, wall_len: float, wall_h: float) -> void:
	var conc: Color = Color(0.6, 0.58, 0.53)
	var brick: Color = GroundKit.COL_BRICK.darkened(0.08)
	var z: float = -wall_h - 60.0
	GroundKit.box(root, Vector3(wall_len * 0.34, 22.0, 34.0), Vector3(0.0, wall_h - 24.0, z), brick)
	GroundKit.box(root, Vector3(wall_len * 0.36, 1.6, 36.0), Vector3(0.0, wall_h - 13.0, z), Color(0.3, 0.29, 0.28), Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		GroundKit.cyl(root, 1.4, 1.8, 22.0, Vector3(sx * 12.0, wall_h - 8.0, z - 6.0), brick.lightened(0.06), Vector3.ZERO, 8)
	GroundKit.box(root, Vector3(wall_len * 0.5, 1.0, 30.0), Vector3(0.0, 2.0, z + 22.0), conc.darkened(0.1), Vector3.ZERO, false)   # tailrace apron
	GroundKit.cyl(root, 3.4, 3.4, 6.0, Vector3(-wall_len * 0.42, 4.0, z), conc, Vector3.ZERO, 10)                                    # surge tank


## Earth/stone valley shoulders that the wall closes: battered embankment banks running out each side.
static func _valley_shoulders(root: Node3D, wall_len: float, wall_h: float) -> void:
	var earth: Color = Color(0.36, 0.31, 0.22)
	var stone: Color = Color(0.48, 0.47, 0.43)
	for sx in [-1.0, 1.0]:
		var x: float = sx * (wall_len * 0.5 + 40.0)
		GroundKit.box(root, Vector3(120.0, wall_h + 12.0, 90.0), Vector3(x, (wall_h + 12.0) * 0.5 - 6.0, 0.0), earth, Vector3(0.0, 0.0, sx * -11.0))
		GroundKit.box(root, Vector3(24.0, wall_h + 16.0, 26.0), Vector3(sx * (wall_len * 0.5 + 6.0), (wall_h + 16.0) * 0.5 - 6.0, 0.0), stone, Vector3(0.0, 0.0, sx * -6.0))


## The anti-torpedo net boom the RAF found across the reservoir (a double line of floats with timber
## spreaders, 30-90 m upstream of the wall) - pure scenery, but it is what the real attack had to clear.
static func _net_boom(root: Node3D, wall_len: float) -> void:
	var steel := Color(0.3, 0.32, 0.34)
	var wood: Color = GroundKit.COL_WOOD
	var z: float = 46.0
	var n: int = 14
	var span: float = wall_len * 0.8
	for line in 2:
		var zz: float = z + float(line) * 26.0
		for i in n + 1:
			var x: float = -span * 0.5 + float(i) * (span / float(n))
			GroundKit.cyl(root, 0.5, 0.6, 1.4, Vector3(x, 0.8, zz), steel, Vector3.ZERO, 6)
			GroundKit.cyl(root, 0.1, 0.1, 4.0, Vector3(x, -1.4, zz), Color(0.2, 0.2, 0.2), Vector3.ZERO, 4, false)
		GroundKit.box(root, Vector3(span, 0.5, 0.6), Vector3(0.0, 1.6, zz), wood, Vector3.ZERO, false)   # timber spreader
