extends Node
## Headless: what building the port / dock / town sites costs (no terrain here, so heights are 0).


func _ready() -> void:
	var p := Vector3(1000, 0, 2000)
	var sea := Vector3(0, 0, -1)
	for rep in 2:
		var jobs: Array = [
			["port s2", func() -> Node3D: return WorldFeatures.build_port(p, sea, 2, "Allies", 11)],
			["port s3", func() -> Node3D: return WorldFeatures.build_port(p, sea, 3, "Allies", 12)],
			["dock basin s2", func() -> Node3D: return WorldFeatures.build_dock_basin(p, sea, 2, "Allies", 13)],
			["pleasure pier", func() -> Node3D: return WorldFeatures.build_pleasure_pier(p, sea, 2, "Allies", 14)],
			["drydock", func() -> Node3D: return WorldFeatures.build_drydock_shipyard(p, sea, 2, "Allies", 15)],
			["fishing harbour", func() -> Node3D: return WorldFeatures.build_fishing_harbour(p, sea, 1, "Allies", 16)],
			["river quay", func() -> Node3D: return WorldFeatures.build_river_quay(p, Vector3(1, 0, 0), 2, "Allies", 17)],
		]
		for j in jobs:
			var t0: int = Time.get_ticks_usec()
			var n: Node3D = (j[1] as Callable).call()
			var t1: int = Time.get_ticks_usec()
			add_child(n)
			var t2: int = Time.get_ticks_usec()
			var cnt: int = n.find_children("*", "", true, false).size()
			print("[siteperf] %-16s build %6.1f ms  into tree %6.1f ms  nodes %d" % [j[0], (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, cnt])
			n.free()
	get_tree().quit()
