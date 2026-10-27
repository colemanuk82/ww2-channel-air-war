extends Node
## Headless: time what building / spawning an aircraft costs on the main thread.
## godot --headless --path . tools/perf/spawn_perf.tscn


func _ready() -> void:
	for id in ["bf109", "spitfire", "he111", "bf109", "spitfire", "he111"]:
		var st: AircraftStats = AircraftCatalog.load_stats(id)
		var t0: int = Time.get_ticks_usec()
		var m: Node3D = AircraftModels.build(st.model_id, st.nation)
		var t1: int = Time.get_ticks_usec()
		m.free()
		var packed: PackedScene = load(AIFactory.AIRCRAFT_SCENE)
		var t2: int = Time.get_ticks_usec()
		var ac: Aircraft = packed.instantiate() as Aircraft
		ac.stats = st
		ac.player_controlled = false
		add_child(ac)
		var t3: int = Time.get_ticks_usec()
		print("[perf] %-9s build %6.1f ms   full spawn %6.1f ms" % [id, (t1 - t0) / 1000.0, (t3 - t2) / 1000.0])
		ac.free()
	# where the build time goes
	var st2: AircraftStats = AircraftCatalog.load_stats("he111")
	var a0: int = Time.get_ticks_usec()
	var raw: Node3D = AircraftModels._build_raw(st2.model_id, st2.nation)
	var a1: int = Time.get_ticks_usec()
	AircraftModels._make_realistic(raw, st2.model_id, st2.nation)
	var a2: int = Time.get_ticks_usec()
	print("[perf] he111 raw build %.1f ms, realistic+livery %.1f ms" % [(a1 - a0) / 1000.0, (a2 - a1) / 1000.0])
	raw.free()
	for id2 in ["spitfire", "bf109", "he111", "lancaster"]:
		var p0: int = Time.get_ticks_usec()
		ParkedAircraft.mesh_for(id2)
		print("[perf] parked mesh %s %.1f ms" % [id2, (Time.get_ticks_usec() - p0) / 1000.0])
	for kind in ["nissen", "blister", "truck", "tent"]:
		var q0: int = Time.get_ticks_usec()
		var gs: GroundStructure = GroundStructure.create("hangar", "Allies", Vector3.ZERO, 0.0)
		add_child(gs)
		print("[perf] hangar structure into tree %.1f ms" % [(Time.get_ticks_usec() - q0) / 1000.0])
		gs.free()
		break
	AircraftModels.free_prototypes()
	get_tree().quit()
