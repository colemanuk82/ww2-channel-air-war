extends SceneTree
# godot --path . --script tools/decal_sheet.gd -- <outdir>   (renders each aircraft model from two angles)
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "F:/ww2_dlss/tools/shots/decals"
	DirAccess.make_dir_recursive_absolute(out)
	var ids: Array = ["spitfire"] + (load("res://scripts/models/model_specs.gd") as GDScript).get("IDS")
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 600)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	vp.add_child(cam)
	for id in ids:
		for nation in (["RAF"] if id in ["spitfire", "hurricane", "typhoon", "mosquito", "tempest", "defiant", "lancaster", "blenheim"] else ["Luftwaffe"] if id in ["bf109", "fw190", "me262", "ju87", "he111", "ju88", "bf110", "do17", "ju52", "fw200"] else ["USAAF"]):
			var m: Node3D = AircraftModels.build(id, nation)
			vp.add_child(m)
			var views := {"a": [Vector3(-9, 7, -9), Vector3(0, 0, 0)], "b": [Vector3(12, 1.5, 3), Vector3(0, 0, 0)], "c": [Vector3(9, 7, 9), Vector3(0, 0.5, 2)]}
			for k in views:
				cam.position = views[k][0] * 0.8
				cam.look_at(views[k][1])
				await process_frame
				await process_frame
				await process_frame
				vp.get_texture().get_image().save_png("%s/%s_%s.png" % [out, id, k])
			m.queue_free()
	quit()
