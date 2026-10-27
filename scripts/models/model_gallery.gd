extends Node3D
## Debug scene: lines up every aircraft model for screenshots.
## godot --path . scenes/model_gallery.tscn -- --shot=gallery.png [--ids=bf109,p51] [--view=side|top|front|three] [--nation=Luftwaffe]

func _ready() -> void:
	var ids: Array = ["spitfire"] + ModelSpecs.IDS
	var view: String = "three"
	var shot: String = ""
	var dist: float = 36.0
	var auto_dist: bool = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids = a.substr(6).split(",")
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--dist="):
			dist = float(a.substr(7))
			auto_dist = false
		elif a.begins_with("--shot="):
			shot = a.substr(7)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var cols: int = 5
	var spacing: float = 62.0
	var built: Array[Node3D] = []
	for i in ids.size():
		var id: String = ids[i]
		var m: Node3D
		if id.begins_with("ground_"):     # --ids=ground_nissen,ground_parked_spitfire ... (airfield props)
			m = _ground_prop(id.substr(7))
		else:
			var st2: AircraftStats = AircraftCatalog.load_stats(id)
			m = AircraftModels.build(st2.model_id, st2.nation)
		m.position = Vector3(float(i % cols - 2) * spacing, 0, float(i / cols) * spacing * 1.1) if ids.size() > 1 else Vector3.ZERO
		add_child(m)
		built.append(m)
	await get_tree().process_frame
	var box: AABB = _bounds_of(built)
	for i in (0 if ids.size() == 1 else built.size()):
		var lbl := Label3D.new()
		lbl.text = ids[i]
		lbl.font_size = 96
		lbl.pixel_size = 0.028 if ids.size() == 1 else 0.12
		lbl.position = built[i].position + Vector3(0, (box.size.y if ids.size() == 1 else 14.0) + 1.0, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)
	var cam := Camera3D.new()
	cam.far = 5000.0
	var rows: int = int(ceil(float(ids.size()) / float(cols)))
	var cz: float = float(rows - 1) * spacing * 0.55
	if ids.size() == 1:
		# frame the whole airframe, so a single-model shot can actually be judged against a 3-view
		var centre: Vector3 = box.get_center()
		var fit: float = 1.2
		var dir: Vector3 = (Vector3(0.8, 0.4, 1.0) if view == "three" else Vector3(0, 1.0, 0.01) if view == "top" else Vector3(1, 0.05, 0) if view == "side" else Vector3(0, 0.1, -1)).normalized()
		if view == "skin":
			# tight on the fuselage so panel lines / grime / chipping can actually be judged
			dir = Vector3(0.55, 0.30, 0.78).normalized()
			fit = 0.30
		if auto_dist:
			dist = max(box.size.length() * 0.5, 1.0) / tan(deg_to_rad(cam.fov * 0.5)) * fit
		cam.look_at_from_position(centre + dir * dist, centre, Vector3.UP if view != "top" else Vector3.FORWARD)
	else:
		cam.fov = 55.0
		cam.position = Vector3(0, 130, cz + 190)
		cam.look_at_from_position(cam.position, Vector3(0, 0, cz), Vector3.UP)
	add_child(cam)
	cam.make_current()
	if shot != "":
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _bounds_of(nodes: Array[Node3D]) -> AABB:
	var out := AABB()
	var first := true
	for n in nodes:
		var all: Array = []
		all.append(n)
		all.append_array(n.find_children("*", "MeshInstance3D", true, false))
		for c in all:
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out


## Airfield props for the gallery: nissen, blister, truck, tent, fuel_tank, parked_<aircraft id>.
func _ground_prop(what: String) -> Node3D:
	var mesh: Mesh
	match what:
		"nissen":
			mesh = AirfieldAssets.nissen("Allies")
		"blister":
			mesh = AirfieldAssets.blister("Allies")
		"truck":
			mesh = AirfieldAssets.truck("Allies")
		"tent":
			mesh = AirfieldAssets.tent("Allies")
		"fuel_tank":
			mesh = AirfieldAssets.fuel_tank()
		_:
			mesh = ParkedAircraft.mesh_for(what.trim_prefix("parked_"))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var n := Node3D.new()
	n.add_child(mi)
	return n
