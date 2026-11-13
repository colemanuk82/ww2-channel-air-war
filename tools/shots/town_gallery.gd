extends Node3D
## Building model gallery (review shots): the ten town house units in a street row, or the landmark buildings.
## Run on the hidden desktop: godot --path . tools/shots/town_gallery.tscn -- --view=houses|back|land --shot=<png>

var _shot: String = ""
var _frames: int = 0


func _ready() -> void:
	var view: String = "houses"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--view="):
			view = a.substr(7)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -140.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.38, 0.24)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	if view == "land":
		var xs: Array = [-55.0, 0.0, 60.0]
		for i in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = TownModels.church(true) if i == 0 else (TownModels.church(false) if i == 1 else TownModels.town_hall())
			mi.position = Vector3(xs[i], 0.0, 0.0)
			mi.rotation.y = 0.0 if i < 2 else PI
			add_child(mi)
		cam.position = Vector3(40.0, 46.0, 120.0)
		cam.look_at(Vector3(0.0, 12.0, 0.0))
	else:
		# two rows: single-house width (7 m) and the wide town-layout unit (12.8 m)
		for row in 2:
			var x: float = -62.0
			for v in 10:
				var w: float = 7.0 if row == 0 else 12.8
				var h: float = 7.0
				var d: float = 8.0
				if v == 9:
					w = 42.0
					h = 9.0
					d = 13.0
				elif v >= 6:
					w *= 1.4
				if v == 9 and row == 1:
					continue
				var mi2 := MeshInstance3D.new()
				mi2.mesh = Scatter.house_mesh(v)
				mi2.scale = Vector3(w, h, d)
				mi2.position = Vector3(x + w * 0.5, h * 0.5, float(row) * 34.0)
				add_child(mi2)
				x += w + 3.0
		if view == "back":
			cam.position = Vector3(-10.0, 34.0, -62.0)
			cam.look_at(Vector3(0.0, 2.0, 14.0))
		else:
			cam.position = Vector3(10.0, 34.0, 96.0)
			cam.look_at(Vector3(0.0, 2.0, 14.0))
		for mi3 in get_children():
			if mi3 is MeshInstance3D and mi3 != ground:
				(mi3 as MeshInstance3D).rotation.y = PI      # street fronts (-Z) toward the camera


func _process(_dt: float) -> void:
	_frames += 1
	if _frames == 40 and _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
