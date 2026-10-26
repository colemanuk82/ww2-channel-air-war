extends Node
## Headless: godot --headless --path . tools/liveries/export_geo.tscn [-- --only=bf109,spitfire]
## Writes tools/liveries/geo/<model>_<nation>.{json,skin.bin,decal.bin} for tools/liveries/paint_liveries.py.


func _ready() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	var done: Dictionary = {}
	if OS.get_cmdline_user_args().has("--dump"):
		for id in only:
			var m: Node3D = AircraftModels.build(id, "RAF" if id == "hurricane" else "Luftwaffe")
			for n in m.find_children("*", "", true, false):
				print("[dump] ", m.get_path_to(n), "  ", n.get_class())
			m.free()
		get_tree().quit()
		return
	for f in DirAccess.get_files_at("res://data/aircraft/"):
		if not f.ends_with(".tres"):
			continue
		var st: Resource = load("res://data/aircraft/" + f)
		if st == null:
			continue
		var id: String = String(st.get("model_id"))
		var nation: String = String(st.get("nation"))
		var k: String = Livery.key(id, nation)
		if done.has(k) or (not only.is_empty() and not only.has(id)):
			continue
		done[k] = true
		print("[livery] ", Livery.export_geo(id, nation, Livery.GEO_DIR))
	print("[livery] EXPORT_DONE")
	get_tree().quit()
