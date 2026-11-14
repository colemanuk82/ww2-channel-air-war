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
	if view == "belfry":
		var bf := MeshInstance3D.new()
		bf.mesh = TownModels.calais_belfry()
		bf.position = Vector3(10.0, 0.0, 0.0)
		bf.rotation.y = -0.5
		add_child(bf)
		for hb in 2:
			var bl := MeshInstance3D.new()
			bl.mesh = AirfieldAssets.blister("Allies" if hb == 0 else "Axis")
			bl.position = Vector3(45.0 + float(hb) * 16.0, 0.0, 50.0)
			bl.rotation.y = -0.6
			add_child(bl)
		cam.position = Vector3(30.0, 60.0, 150.0)
		cam.look_at(Vector3(5.0, 28.0, 0.0))
		cam.fov = 45.0
	elif view == "cath":
		var cspecs: Array = [[150.0, 46.0, 157.0, 2, 28.0, Color(0.34, 0.33, 0.32), false, false], [100.0, 34.0, 60.0, 1, 14.0, Color(0.66, 0.62, 0.54), true, false], [130.0, 34.0, 68.0, 2, 48.0, Color(0.78, 0.74, 0.64), false, false]]
		for ci2 in 3:
			var cs: Array = cspecs[ci2]
			var cm2 := MeshInstance3D.new()
			cm2.mesh = TownModels.cathedral(cs[0], cs[1], cs[2], cs[3], cs[4], cs[5], cs[6], cs[7])
			cm2.position = Vector3(-130.0 + float(ci2) * 130.0, 0.0, 0.0)
			cm2.rotation.y = 0.6
			add_child(cm2)
		sun.directional_shadow_max_distance = 900.0
		cam.position = Vector3(40.0, 150.0, 360.0)
		cam.look_at(Vector3(0.0, 55.0, 0.0))
		cam.fov = 45.0
	elif view == "mills":
		var wm: Node3D = Landmarks.windmill()
		wm.position = Vector3(-16.0, 0.0, 0.0)
		wm.rotation.y = PI + 0.5
		add_child(wm)
		var lh: Node3D = Landmarks.lighthouse(40.0)
		lh.position = Vector3(18.0, 0.0, 0.0)
		lh.rotation.y = PI + 0.3
		add_child(lh)
		cam.position = Vector3(0.0, 30.0, 75.0)
		cam.look_at(Vector3(0.0, 18.0, 0.0))
		cam.fov = 45.0
	elif view == "props":
		gm.albedo_color = Color(0.36, 0.40, 0.28)
		var pmeshes: Array = [AirfieldAssets.nissen("Allies"), AirfieldAssets.tent("Allies"), AirfieldAssets.fuel_tank()]
		for pi in 3:
			var pmi := MeshInstance3D.new()
			pmi.mesh = pmeshes[pi]
			pmi.position = Vector3(-14.0 + float(pi) * 13.0, 0.0, 0.0)
			pmi.rotation.y = -0.5
			add_child(pmi)
		cam.position = Vector3(4.0, 13.0, 26.0)
		cam.look_at(Vector3(0.0, 2.0, 0.0))
		cam.fov = 50.0
	elif view == "vehicles":
		gm.albedo_color = Color(0.36, 0.40, 0.28)
		var vk: Array = ["truck", "bowser", "firetender", "halftrack", "kubel", "jeep", "car", "bus"]
		var vc: Color = GroundKit.team_color("Allies")
		var q: int = 0
		for kd2 in vk:
			var vmi := MeshInstance3D.new()
			var col3: Color = vc
			if kd2 == "firetender":
				col3 = Color(0.72, 0.12, 0.1)
			elif kd2 == "car":
				col3 = Color(0.14, 0.26, 0.17)
			elif kd2 == "bus":
				col3 = Color(0.55, 0.12, 0.1)
			vmi.mesh = TownModels.vehicle(kd2, col3)
			vmi.position = Vector3(-14.0 + float(q % 4) * 9.0, 0.0, -4.0 + float(q / 4) * 9.0)
			vmi.rotation.y = 0.5
			add_child(vmi)
			q += 1
		cam.position = Vector3(2.0, 14.0, 20.0)
		cam.look_at(Vector3(0.0, 1.0, 0.0))
		cam.fov = 50.0
	elif view == "tanks":
		gm.albedo_color = Color(0.36, 0.40, 0.28)
		var specs: Array = [["sherman", "Allies", 5.8, 2.6, 0.9, 1.0, 0.0, false], ["panzer4", "Axis", 5.9, 2.8, 0.9, 1.0, 1.0, true], ["tiger", "Axis", 7.0, 3.6, 1.1, 1.1, 1.8, true]]
		var kk: int = 0
		for sp in specs:
			var cc2: Color = GroundKit.team_color(sp[1])
			var th := MeshInstance3D.new()
			th.mesh = TownModels.tank_hull(cc2, sp[2], sp[3], sp[4], sp[7])
			th.position = Vector3(-9.0 + float(kk) * 9.0, 0.0, 0.0)
			th.rotation.y = 0.5
			add_child(th)
			var tu := MeshInstance3D.new()
			tu.mesh = TownModels.tank_turret(cc2, sp[2], sp[3], sp[5], 3.2 + sp[6], sp[6] > 0.0)
			tu.position = Vector3(0.0, 0.75 + sp[4], -0.2)
			th.add_child(tu)
			kk += 1
		cam.position = Vector3(2.0, 9.0, 16.0)
		cam.look_at(Vector3(0.0, 1.0, 0.0))
		cam.fov = 50.0
	elif view == "guns":
		gm.albedo_color = Color(0.36, 0.40, 0.28)
		for gi in 2:
			var big: bool = gi == 1
			var tt: String = "88mm" if big else "bofors"
			var cc: Color = GroundKit.team_color("Axis")
			var holder := Node3D.new()
			holder.position = Vector3(-8.0 + float(gi) * 16.0, 0.0, 0.0)
			add_child(holder)
			var m1 := MeshInstance3D.new()
			m1.mesh = AAGun._static_mesh(tt)
			holder.add_child(m1)
			var m2 := MeshInstance3D.new()
			m2.mesh = AAGun._yaw_mesh(tt, "Axis")
			holder.add_child(m2)
			var m3 := MeshInstance3D.new()
			m3.mesh = AAGun._pitch_mesh(tt, "Axis")
			m3.position = Vector3(0.0, 2.4, 0.0)
			m3.rotation_degrees = Vector3(35.0, 0.0, 0.0)
			holder.add_child(m3)
		cam.position = Vector3(2.0, 14.0, 18.0)
		cam.look_at(Vector3(0.0, 2.0, 0.0))
		cam.fov = 50.0
	elif view == "bridge":
		var bmi := MeshInstance3D.new()
		bmi.mesh = TownModels.strike_bridge()
		add_child(bmi)
		gm.albedo_color = Color(0.10, 0.20, 0.30)
		cam.position = Vector3(70.0, 55.0, 110.0)
		cam.look_at(Vector3(0.0, 14.0, 0.0))
		cam.fov = 45.0
	elif view == "hangars":
		gm.albedo_color = Color(0.36, 0.40, 0.28)
		var hm1 := MeshInstance3D.new()
		hm1.mesh = AirfieldAssets.t2_hangar("Allies")
		hm1.position = Vector3(-30.0, 0.0, 0.0)
		hm1.rotation.y = PI
		add_child(hm1)
		var hm2 := MeshInstance3D.new()
		hm2.mesh = AirfieldAssets.t1_hangar("Allies")
		hm2.position = Vector3(30.0, 0.0, 0.0)
		hm2.rotation.y = PI
		add_child(hm2)
		cam.position = Vector3(10.0, 50.0, -95.0)
		cam.look_at(Vector3(0.0, 2.0, 0.0))
		cam.fov = 55.0
	elif view == "ships":
		gm.albedo_color = Color(0.10, 0.20, 0.30)
		var kinds: Array = ["destroyer", "cruiser", "battleship", "freighter", "collier", "trawler", "ferry", "landing_craft", "fishing_boat"]
		var z: float = -20.0
		var k: int = 0
		for kd in kinds:
			var cfg: Dictionary = GroundShip.TYPES[kd]
			var mi4 := MeshInstance3D.new()
			mi4.mesh = ShipModels.build(kd, true, float(cfg["len"]), float(cfg["beam"]))
			mi4.position = Vector3(-60.0 + float(k % 3) * 60.0, 0.0, -60.0 + float(k / 3) * 46.0)
			mi4.rotation.y = PI * 0.5 + 0.35
			add_child(mi4)
			k += 1
		cam.position = Vector3(30.0, 90.0, 110.0)
		cam.look_at(Vector3(0.0, 0.0, -20.0))
	elif view == "land":
		var xs: Array = [-55.0, 0.0, 60.0]
		for i in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = TownModels.church(true) if i == 0 else (TownModels.market_square() if i == 1 else TownModels.town_hall())
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

