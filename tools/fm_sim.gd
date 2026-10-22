extends Node
## Headless flight-model harness: hands-off level-flight hold for every aircraft type.
const DT := 1.0 / 60.0

func _ready() -> void:
	var only: String = ""
	var assist: bool = false
	var secs: float = 120.0
	var thrs: Array = [0.45, 0.6, 0.75, 0.9]
	var y_start: float = 600.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.substr(7)
		if a == "--assist": assist = true
		if a.begins_with("--secs="): secs = float(a.substr(7))
		if a.begins_with("--thr="):
			thrs = []
			for v in a.substr(6).split(","): thrs.append(float(v))
		if a.begins_with("--alt="): y_start = float(a.substr(6)) * 2.0
	var scene: PackedScene = load("res://scenes/aircraft/aircraft_base.tscn")
	var files: PackedStringArray = DirAccess.get_files_at("res://data/aircraft")
	for f in files:
		if not f.ends_with(".tres"): continue
		if only != "" and not f.begins_with(only): continue
		var st: AircraftStats = load("res://data/aircraft/" + f)
		for thr in thrs:
			var ac: Aircraft = scene.instantiate()
			ac.stats = st
			ac.player_controlled = true
			add_child(ac)
			ac.set_process(false)
			ac.auto_level = assist
			ac.reset_pose(Vector3(0, y_start, 0), 90.0, true, st.max_speed * 0.62)
			if OS.get_cmdline_user_args().has("--kick"):
				ac.rotate_object_local(Vector3.RIGHT, deg_to_rad(6.0))
				ac._path_dir = ac.get_forward()
			ac.throttle = thr
			ac.throttle_target = thr
			var y0: float = ac.global_position.y
			var mn: float = 1e9
			var mx: float = -1e9
			var t: float = 0.0
			var line: String = ""
			while t < secs:
				ac._process(DT)
				t += DT
				var am: float = ac.get_altitude_m()
				if t > 20.0:
					mn = minf(mn, am); mx = maxf(mx, am)
				if OS.get_cmdline_user_args().has("--diag") and fmod(t, 1.0) < DT and t < 25.0:
					print("  t%4.1f alt %6.1f spd %5.1f eas %5.1f pitch %+5.1f alpha %+5.2f trim %+5.2f n %4.2f pathy %+.3f stall %.2f" % [t, am, ac.speed, ac.eas, rad_to_deg(ac._pitch_angle()), rad_to_deg(ac._alpha_signed()), rad_to_deg(WingModel.trim_alpha(ac.stats.stall_speed, ac.eas, 0.0)), ac.g_load, ac._path_dir.y, ac._stall_amount])
				if fmod(t, 20.0) < DT:
					line += " %4.0fm/%3.0f" % [am, ac.speed]
			var vs: float = ac.velocity.y / WorldCoords.VERTICAL_SCALE
			print("%-14s thr %.2f  alt/spd:%s | 20s+ range %.0f..%.0f m  end vs %+.1f m/s %s" % [f.get_basename(), thr, line, mn, mx, vs, "STALL" if ac.stalled else ""])
			ac.queue_free()
	get_tree().quit()
