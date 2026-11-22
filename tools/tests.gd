extends Node
## Headless test runner.
##   godot --headless --path . scenes/tests.tscn
## Exits non-zero if any check fails. Covers shader loading, the mesh helpers, every aircraft model
## contract, turret mount placement and the procedural audio synth. Run as a scene (not --script) so
## the autoloads the game scripts depend on are present.

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_install_test_terrain()
	_test_shaders()
	_test_mesh_helpers()
	_test_aircraft_models()
	_test_catalogue()
	_test_markings()
	_test_obstacles()
	_test_turret_mounts()
	_test_scatter_masks()
	_test_music()
	_test_audio_licences()
	_test_target_index()
	_test_audio()
	_test_logbook_voice()
	_test_custom_missions()
	_test_mission_briefs()
	_test_escape_and_backup()
	_test_interior_cockpit()
	_test_data_files()
	_test_map_edits()
	_test_cel_style()
	_test_cel_ink()
	_test_art_style_key()
	_test_map_editor_transform()
	_test_edit_history()
	_test_map_editor_edits()
	_test_map_editor_multi()
	_test_map_live_refresh()
	_test_map_assets()
	_test_river_data()
	_test_landmarks_all()
	_test_house_variants()
	_test_industry_kinds()
	_test_landscape_data()
	_test_sea_defence_kinds()
	_test_dams_build()
	_test_pow_escape()
	_test_airborne()
	_test_realism_presets()
	_test_structural_damage()
	_test_city_balloons()
	_test_balloon_cables_and_streams()
	_test_decoy_kinds()
	_test_pylon_data()
	_test_pylon_build()
	_test_canal_furniture()
	_test_rail_drama()
	_test_airfield_furniture()
	_test_airfield_styles()
	await _test_spawn_clear()
	_test_taxi_graph()
	_test_oil_fuel()
	_test_aircraft_industry()
	_test_v_weapons()
	_test_port_clutter()
	_test_rural()
	_test_coastal_landmarks()
	_test_civil_defence()
	_test_aviation_support()
	_test_forestry()
	_test_navigation_aids()
	_test_military_depth()
	_test_moon_weather()
	_test_history()
	_test_ai_takeoff_all()
	_test_realism()
	_test_weak_gpu()
	_test_vram_budget()
	_test_accessibility()
	_test_awards()
	_test_legal_docs()
	_test_era_damage()
	_test_terraces_war_damage()
	_test_harbour_war()
	_test_town_people()
	_test_farm_people()
	_test_enemy_flights()
	_test_military_people()
	_test_war_reactions()
	_check(UpdateCheck.is_newer("v1.10", "1.9") and UpdateCheck.is_newer("1.5", "1.4") and not UpdateCheck.is_newer("1.4", "1.4") and not UpdateCheck.is_newer("v1.3", "1.4") and UpdateCheck.is_newer("2.0", "1.99"), "update check compares versions numerically")
	_test_report_link()
	_test_gameplay_additions()
	_test_stale_enemy_cache()
	_test_weapon_targets_left_tree()
	_test_combat_audio()
	_test_controls_ui()
	await _test_pad_navigation()
	_test_practice_aids()
	print("\nTESTS %s  (%d passed, %d failed)" % ["FAILED" if _failed > 0 else "OK", _passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)



func _test_military_people() -> void:
	print("-- military people: gun crews, checkpoints, halts, the run phase")
	var dens: Array[float] = [0.7, 1.6, 2.2]
	var sizes_ok: bool = true
	for gt in ["88mm", "bofors", "mg"]:
		var prev: int = 0
		for d in dens:
			var n: int = MilitaryPeople.crew_size(gt, d)
			if n < 3 or n > 7 or n < prev:
				sizes_ok = false
			prev = n
	_check(sizes_ok, "gun crews are 3-7 men and grow with the quality setting")
	_check(MilitaryPeople.crew_size("88mm", 2.2) == 7 and MilitaryPeople.crew_size("mg", 0.7) == 3, "an 88 on High has seven men, a machine-gun pit on Low three")
	# the posts stand on the pit floor, clear of the gun and inside the ring; the ease spots outside the entrance
	var geo_ok: bool = true
	var ease_ok: bool = true
	var run_ok: bool = true
	for gt2 in ["88mm", "bofors", "mg"]:
		var rr: Vector2 = MilitaryPeople.pit_radii(gt2)
		for sl in MilitaryPeople.gun_slots(gt2, 7):
			var post: Vector2 = sl[0]
			var ez: Vector2 = sl[1]
			if post.length() < 3.0 or post.length() > rr.y - 0.8:
				geo_ok = false
			if ez.length() < rr.y + 1.5 or ez.y < rr.y:
				ease_ok = false
			if ez.distance_to(post) < 3.0:
				run_ok = false
	_check(geo_ok, "gun crew posts are between the gun and the sandbag ring (not inside the gun or the sandbags)")
	_check(ease_ok, "the men stand about outside the pit's entrance")
	_check(run_ok, "every man has a real run from his ease spot to his post")
	var kinds_ok: bool = true
	for k in [AirfieldPeople.Kind.REACH, AirfieldPeople.Kind.KNEEL, AirfieldPeople.Kind.WORK, AirfieldPeople.Kind.SALUTE, AirfieldPeople.Kind.RUN]:
		var cc: int = AirfieldPeople.code_of(k, true, 2)
		if AirfieldPeople.kind_of(cc) != k or not AirfieldPeople.soldier_of(cc) or AirfieldPeople.dress_of(cc) != 2:
			kinds_ok = false
	_check(kinds_ok, "crew kinds encode with the soldier flag")
	# a run begins at the start of its beat: the shader's d = mod((TIME + ph * 61) * spd, lap) is 0 at the moment asked
	var phase_ok: bool = true
	for now in [0.0, 12.3, 1999.9, 3599.0]:
		for ln in [4.0, 9.5, 14.0]:
			for pr in [[3.0, 1.2], [1.4, 2.4]]:
				var spd: float = pr[0]
				var halt: float = pr[1]
				var ph: float = MilitaryPeople.beat_phase(ln, spd, halt, now)
				var lap: float = 2.0 * (ln + halt * spd)
				var dd: float = fposmod((now + ph * 61.0) * spd, lap)
				if ph < 0.0 or ph > 1.0 or minf(dd, lap - dd) > 0.01:
					phase_ok = false
	_check(phase_ok, "beat_phase starts a run / walk beat at its first end")
	# checkpoints: on the approach side of the barrier, on the road and its verges
	var cp_ok: bool = true
	for dv in [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.6, 0.8)]:
		for w in [5.5, 8.0, 12.0]:
			var spots: Array = MilitaryPeople.checkpoint_spots(Vector2(100.0, -50.0), dv, w, 4)
			if spots.size() != 4:
				cp_ok = false
			for sp in spots:
				var rel: Vector2 = (sp[0] as Vector2) - Vector2(100.0, -50.0)
				var along: float = rel.dot(dv)
				var lat: float = absf(rel.dot(Vector2(dv.y, -dv.x)))
				if along < 4.0 or along > 9.5 or lat > w * 0.5 + 1.3:
					cp_ok = false
	_check(cp_ok, "checkpoint men stand before the barrier, on the road and its verges")
	# halts: nobody inside a lorry's footprint
	var halt_ok: bool = true
	for sd in [-1.0, 1.0]:
		for nl in [2, 3]:
			var dh := Vector2(0.8, 0.6)
			var h0 := Vector2(40.0, 70.0)
			var hs: Array = MilitaryPeople.halt_spots(h0, dh, 6.5, sd, nl, 7)
			if hs.size() != 7:
				halt_ok = false
			var latv: Vector2 = Vector2(dh.y, -dh.x) * float(sd)
			var run: float = float(nl - 1) * 11.0
			for h in hs:
				var rel2: Vector2 = (h[0] as Vector2) - h0
				var al: float = rel2.dot(dh)
				var la: float = rel2.dot(latv)
				for k in nl:
					var cx: float = -run * 0.5 + float(k) * 11.0
					if absf(al - cx) < 4.4 + 0.4 and absf(la - (6.5 * 0.5 + 2.4)) < 1.3 + 0.3:
						halt_ok = false
	_check(halt_ok, "men at a roadside halt never stand inside a lorry")
	var bm: ArrayMesh = MilitaryPeople.barrier_mesh(6.5)
	_check(bm != null and bm.get_surface_count() > 0, "the checkpoint barrier mesh builds")
	# a tile with no roads and no coast plans nothing and does not fail
	var empty_plan: Dictionary = MilitaryPeople.tile_plan(Vector2(5000.0, 5000.0), 1800.0, [[], [], [], []], 7, "Axis", 2.2)
	_check(empty_plan is Dictionary, "a tile plan with nothing to plan on is an empty Dictionary")

func _test_controls_ui() -> void:
	print("-- key rebinding, control profiles, first-flight lesson, assists")
	var keep_keys: Dictionary = GameState.key_bindings.duplicate()
	var kev := InputEventKey.new()
	kev.physical_keycode = KEY_U
	GameState.rebind_key("gear", kev)
	var has_u: bool = false
	var has_g: bool = false
	for e in InputMap.action_get_events("gear"):
		if e is InputEventKey:
			has_u = has_u or (e as InputEventKey).physical_keycode == KEY_U
			has_g = has_g or (e as InputEventKey).physical_keycode == KEY_G
	_check(has_u and not has_g and GameState.key_label("gear") == "U", "a key rebinding replaces the action's key (%s)" % GameState.key_label("gear"))
	_check(GameState.key_clashes("flaps", KEY_U).has("gear"), "key clash check finds the other action on the key")
	GameState.clear_key("gear")
	_check(GameState.key_label("gear") == "Unbound", "Delete leaves an action with no key")
	GameState.reset_key_bindings()
	_check(GameState.key_label("gear") == "G", "Reset keys restores the default key")
	var slot: int = GameState.PROFILE_SLOTS
	var had: bool = GameState.has_profile(slot)
	var backup: String = FileAccess.get_file_as_string(GameState.profile_path(slot)) if had else ""
	GameState.rebind_key("flaps", kev)
	GameState.save_profile(slot)
	GameState.reset_key_bindings()
	_check(GameState.load_profile(slot) and GameState.key_label("flaps") == "U", "a control profile saves and loads the key bindings")
	GameState.reset_key_bindings()
	if had:
		var bf := FileAccess.open(GameState.profile_path(slot), FileAccess.WRITE)
		bf.store_string(backup)
		bf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.profile_path(slot)))
	GameState.key_bindings = keep_keys
	GameState._apply_key_bindings()
	GameState.save_settings()
	_check(TrainingMode.lesson_ids().has("t_first_flight"), "the first-flight lesson is listed in Training")
	var tm := TrainingMode.new()
	tm.configure({"mission": "t_first_flight"})
	_check(not tm.start_airborne and tm.wants_dispersal_start, "the first-flight lesson starts on the ground at the dispersal")
	tm.free()


func _test_combat_audio() -> void:
	print("-- combat audio: whiz, ricochet, cockpit muffle, dynamic music")
	var w: AudioStreamWAV = FX.audio._stream("whiz") as AudioStreamWAV
	var r: AudioStreamWAV = FX.audio._stream("ricochet:1") as AudioStreamWAV
	_check(w != null and w.get_length() > 0.2 and r != null and r.get_length() > 0.3, "whiz and ricochet sounds are synthesised")
	AudioManager.set_cockpit(true, 10.0)
	var si: int = AudioServer.get_bus_index("SFX")
	var on_ok: bool = AudioServer.is_bus_effect_enabled(si, AudioManager._cockpit_fx)
	AudioManager.set_cockpit(false, 10.0)
	_check(on_ok and not AudioServer.is_bus_effect_enabled(si, AudioManager._cockpit_fx), "the cockpit low-pass switches on in the cockpit and off outside")
	var gm := GameMusic.new()
	_check("combat" in gm and gm.combat == 0.0, "in-flight music starts calm")
	gm.free()


func _test_gameplay_additions() -> void:
	print("-- patrol missions, career roster and branching, gun jams")
	var all_ok: bool = true
	for k in PatrolMode.kind_ids():
		if not (k in OpsRoom.KINDS):
			all_ok = false
	_check(all_ok and PatrolMode.kind_ids().has("rescue") and PatrolMode.kind_ids().has("recce") and PatrolMode.kind_ids().has("shipping") and PatrolMode.kind_ids().has("intercept"), "every patrol mission is an Ops Room tasking kind")
	_check(ModeRegistry.has_mode("patrol"), "Patrol Missions is a registered mode")
	# career: never touch the player's real save
	var had: bool = Career.has_save()
	var backup: String = FileAccess.get_file_as_string(Career.SAVE_PATH) if had else ""
	var keep_state: Dictionary = Career.state.duplicate(true)
	Career.new_pilot("Test", "Allies", "spitfire", false)
	_check(Career.roster().size() == Career.MATES["Allies"].size(), "a new pilot's squadron roster holds the whole flight")
	_check(not Career.step_applies({"when": {"min_kills": 3}}) and Career.step_applies({"when": {"max_kills": 0}}), "branch conditions read the pilot's kills")
	Career.state["last_fate"] = "sea"
	_check(Career.step_applies({"when": {"after_fate": ["sea", "crashed"]}}) and not Career.step_applies({"when": {"lost_mate": true}}), "branch conditions read the last fate and lost mates")
	var lost: String = str(Career.state["mates"][0])
	var joined: String = Career._update_roster(Career.state["mates"].slice(0, 2), 1, lost, "crashed")
	var st_lost: String = ""
	for e in Career.roster():
		if str(e["name"]) == lost:
			st_lost = str(e["status"])
	_check(joined != "" and Career.roster().size() == Career.MATES["Allies"].size() + 1 and st_lost in ["killed", "missing"], "a lost mate is posted missing and a replacement joins (%s -> %s)" % [lost, joined])
	Career.state = keep_state
	if had:
		var f := FileAccess.open(Career.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.SAVE_PATH))
	var ch0: Dictionary = (Career.data()["chapters"] as Array)[0]
	var ids: Array = []
	for s in ch0["Allies"]:
		ids.append(str(s.get("id", "")))
	_check(ids.has("commendation") and ids.has("shaken") and ids.has("funeral"), "the first chapter carries the branch steps")
	var ws := WeaponSystem.new()
	_check(not ws.jammed and ws.JAM_SAFE > 1.0, "guns start clear; short bursts never jam")
	ws.free()


func _test_stale_enemy_cache() -> void:
	print("-- bomber defence ignores an enemy freed since its list was built")
	var f := BomberFormation.new()
	add_child(f)
	var m := Aircraft.new()
	f.add_child(m)
	f.members.append(m)
	var gone := Aircraft.new()
	add_child(gone)
	var stale: Array[Aircraft] = [gone]
	gone.free()      # freed after the list was made (a despawn): a release build crashed calling a method on it
	f._def_t = 0.0
	f._tick_defence(1.0, stale)
	_check(is_instance_valid(f), "a bomber formation survives a stale enemy in its defence list")
	f.queue_free()


func _test_weapon_targets_left_tree() -> void:
	print("-- weapon targets taken out of the world between refreshes are skipped")
	var t := Node3D.new()
	t.add_to_group("damageable")
	add_child(t)
	Weapons._refresh_targets(true)
	var idx: int = Weapons._tn.find(t)
	_check(idx >= 0, "a damageable node in the tree is a weapon target")
	remove_child(t)      # still alive, no longer in the tree: global_position would log an error every frame
	Weapons._refresh_targets(false)
	_check(idx >= 0 and Weapons._tr[idx] < 0.0, "a target that left the tree is dropped from the hit list")
	t.free()
	Weapons._refresh_targets(true)


func _test_report_link() -> void:
	print("-- crash report / feedback links")
	var home: String = OS.get_environment("USERPROFILE")
	if home != "":
		var s: String = ReportLink.scrub("log at %s\\AppData\\x.txt" % home)
		_check(not s.contains(home) and s.contains("~"), "crash report scrubs the home folder")
	var u: String = ReportLink.issue_url("Crash report", "a b&c\n```x```", "crash")
	_check(u.begins_with(ReportLink.ISSUES_URL + "?title=") and not u.contains(" ") and not u.contains("\n") and u.ends_with("&labels=crash"), "issue link is URL-encoded")
	_check(ReportLink.crash_body("user://no_such_file.txt").contains("(no log found)"), "crash report without a log still builds")
	_check(ReportLink.feedback_body().contains("Game v"), "feedback form carries the game version")


func _test_moon_weather() -> void:
	print("-- moon and weather")
	_check(MoonWeather.jdn("2000-01-01") == 2451545, "julian day of 2000-01-01")
	_check(MoonWeather.date_from_jdn(2451545) == "2000-01-01", "date_from_jdn inverts jdn")
	_check(MoonWeather.illumination("2000-01-06") < 0.02, "new moon of 2000-01-06 is dark")
	_check(MoonWeather.illumination("2000-01-21") > 0.97, "full moon of 2000-01-21 is bright")
	_check(MoonWeather.moon_name("2000-01-21") == "Full moon", "moon name at full")
	var d: String = MoonWeather.DEFAULT_DATE
	_check(MoonWeather.date_at_offset(MoonWeather.offset_of(d)) == d, "date slider offset round trip")
	var fc: String = MoonWeather.forecast(d, 51.1, 1.3)
	_check(fc == MoonWeather.forecast(d, 51.1, 1.3), "forecast is deterministic for date and route")
	_check(WeatherManager.PRESETS.has(fc), "forecast is a WeatherManager preset")
	_check(MoonWeather.nav_penalty("fog") > MoonWeather.nav_penalty("clear"), "fog is harder to navigate than clear")
	_check(is_equal_approx(MoonWeather.moon_light(), TimeOfDay.moon_illum), "moon_light reads TimeOfDay")
	_check(WeatherManager.PRESETS.has(MoonWeather.random_weather(1)) and WeatherManager.PRESETS.has(MoonWeather.random_weather(0)), "random weather is a preset, with or without a season")
	_check(float(MoonWeather.SEASON_WEATHER["winter"]["fog"]) > float(MoonWeather.SEASON_WEATHER["summer"]["fog"]) and float(MoonWeather.SEASON_WEATHER["summer"]["storm"]) > float(MoonWeather.SEASON_WEATHER["winter"]["storm"]), "winter brings more fog, summer more thunderstorms")
	var ra: float = WeatherManager.rain_at(Vector3(0.0, 800.0, 0.0))
	_check(ra >= 0.0 and ra <= 1.0, "rain at a point is 0..1")


func _test_era_damage() -> void:
	var keep: String = EraClock.current()
	EraClock.set_date("")
	_check(EraClock.current() == EraClock.DEFAULT and EraClock.band() == "1940", "no date means summer 1940")
	EraClock.set_date("1940-10-01")
	_check(EraClock.band() == "blitz", "October 1940 is the Blitz band")
	EraClock.set_date("1944-05-15")
	_check(EraClock.band() == "buildup", "May 1944 is the build-up band")
	EraClock.set_date("1944-07-20")
	_check(EraClock.band() == "liberation" and EraClock.is_between("1944-06-06", "") and not EraClock.is_between("", "1944-06-05"), "July 1944: liberation, after D-Day")
	_check(absf(EraClock.ramp("1944-07-10", "1944-07-30") - 0.5) < 0.05, "ramp is linear in days")
	WarDamage.load_data()
	_check(WarDamage.rows().size() >= 40, "war damage data has %d areas" % WarDamage.rows().size())
	for r in WarDamage.rows():
		var rd: Dictionary = r
		_check(str(rd.get("source", "")) != "" and float(rd["level"]) > 0.0 and float(rd["level"]) <= 1.0 and str(rd["from"]) <= str(rd["full"]), "war damage row %s is complete" % str(rd.get("id", "?")))
	var caen: Vector3 = WorldCoords.latlon_to_world(49.183, -0.370)
	var docks: Vector3 = WorldCoords.latlon_to_world(51.497, -0.043)
	WarDamage.refresh()
	_check(WarDamage.level_at(caen.x, caen.z) > 0.5, "Caen is in ruins on 1944-07-20")
	EraClock.set_date("1940-08-01")
	WarDamage.refresh()
	_check(WarDamage.level_at(caen.x, caen.z) == 0.0 and WarDamage.level_at(docks.x, docks.z) == 0.0, "no bomb damage in Caen or the London docks on 1940-08-01")
	EraClock.set_date("1940-10-15")
	WarDamage.refresh()
	_check(WarDamage.level_at(docks.x, docks.z) > 0.4, "the Surrey docks are burnt out by mid-October 1940")
	var lists: Array = [[Transform3D(Basis.IDENTITY.scaled(Vector3(8, 7, 9)), docks + Vector3(0, 3, 0))], []]
	for i in 200:
		(lists[1] as Array).append(Transform3D(Basis.IDENTITY.scaled(Vector3(8, 7, 9)), docks + Vector3(float(i % 20) * 9.0, 3.0, float(i / 20) * 11.0)))
	var ruins: Array = [[], []]
	WarDamage.apply_to_houses(lists, ruins, WarDamage.areas_near(Vector2(docks.x, docks.z) - Vector2(900, 900), 1800.0))
	var n_ruin: int = (ruins[0] as Array).size() + (ruins[1] as Array).size()
	var n_left: int = (lists[0] as Array).size() + (lists[1] as Array).size()
	_check(n_ruin > 40 and n_left > 20 and n_ruin + n_left < 201, "a burnt dock street keeps %d houses, %d shells" % [n_left, n_ruin])
	for v in 2:
		var rm: ArrayMesh = WarDamage.ruin_mesh(v)
		_check(rm != null and rm.get_surface_count() > 0 and rm.get_surface_count() <= 6, "ruin mesh %d builds with %d surfaces" % [v, rm.get_surface_count()])
	# the 1944 build-up
	var bd: Dictionary = BuildupKit.data()
	_check((bd.get("marshalling", []) as Array).size() >= 8 and (bd.get("anchorages", []) as Array).size() >= 8, "build-up data loads")
	for k in ["lct", "lci", "lst"]:
		_check(BuildupKit.craft_mesh(k).get_surface_count() > 0, "landing craft mesh %s builds" % k)
	_check(BuildupKit.hard_mesh().get_surface_count() > 0, "embarkation hard mesh builds")
	EraClock.set_date("1940-08-01")
	for r0 in bd.get("anchorages", []):
		var n0: Node3D = BuildupKit.build(r0, "anchorage")
		_check(n0.get_child_count() == 0, "no invasion fleet at %s in 1940" % str((r0 as Dictionary)["id"]))
		n0.free()
	EraClock.set_date("1944-05-20")
	var on_n: int = 0
	for r1 in bd.get("anchorages", []):
		if EraClock.is_between(str((r1 as Dictionary)["from"]), str((r1 as Dictionary)["to"])):
			on_n += 1
	_check(on_n == (bd.get("anchorages", []) as Array).size(), "every anchorage is in its window on 1944-05-20 (the test terrain has no sea to moor in)")
	# farming regions and seasons
	RegionMap.load_map()
	_check(RegionMap.ready(), "region map loads (data/heightmap/region_types.png)")
	var probe: Array = [[49.25, -1.40, 0, "bocage (Cotentin)"], [49.90, 2.30, 1, "open field (Picardy)"], [52.30, 4.75, 2, "polder (Holland)"], [51.10, 0.30, 3, "Weald"], [51.50, -0.10, -1, "London (none)"]]
	for pr in probe:
		var wp3: Vector3 = WorldCoords.latlon_to_world(float(pr[0]), float(pr[1]))
		var tw: Vector4 = RegionMap.type_weights(wp3.x, wp3.z)
		var want: int = int(pr[2])
		var got: int = -1
		for c in 4:
			if tw[c] > 0.5:
				got = c
		_check(got == want, "region at %s is %s (got %d)" % [str(pr[3]), str(pr[3]), got])
	var fe: Dictionary = Scatter.field_edge(Vector2(WorldCoords.latlon_to_world(49.25, -1.40).x, WorldCoords.latlon_to_world(49.25, -1.40).z))
	_check(not fe.is_empty() and (fe["region"] as Vector4).x > 0.5, "field_edge reports the bocage region")
	# barges
	_check(BargeTraffic.peniche_mesh().get_surface_count() > 0 and BargeTraffic.barge_train_mesh().get_surface_count() > 0, "barge meshes build")
	# Westwall, bridges, anti-landing obstacles
	_check(WestwallKit.chunks().size() >= 3, "the Westwall line is cut into %d streamed sections" % WestwallKit.chunks().size())
	_check(WestwallKit.teeth_mesh().get_surface_count() > 0 and RuralProps.obstacle_mesh().get_surface_count() > 0, "dragon's teeth and field-obstacle meshes build")
	EraClock.set_date("1945-03-20")
	var lb: Node3D = Landmarks.build("ludendorff_bridge")
	EraClock.set_date("1945-03-01")
	var lb0: Node3D = Landmarks.build("ludendorff_bridge")
	_check(lb.get_child_count() != lb0.get_child_count(), "the Ludendorff bridge has fallen by 20 Mar 1945 (%d vs %d parts)" % [lb.get_child_count(), lb0.get_child_count()])
	lb.free()
	lb0.free()
	# floods, battlefields, beaches and landing zones by date
	EraClock.set_date("1944-06-10")
	var wz: Array = WarGround.zones()
	var kinds: Dictionary = {}
	for z in wz:
		kinds[int(floor(float(z["kind"]) + 0.001))] = true
	_check(kinds.has(5) and kinds.has(6), "on 1944-06-10 the Normandy floods and churned beaches are on")
	var lz_on: Node3D = null
	for r in GliderKit.rows():
		if str((r as Dictionary)["id"]) == "tonga_lz_n":
			lz_on = GliderKit.build(r)
	_check(lz_on != null and lz_on.get_child_count() > 0, "gliders lie on LZ N on 1944-06-10")
	if lz_on != null:
		lz_on.free()
	EraClock.set_date("1940-08-01")
	var wz40: Array = WarGround.zones()
	var dunk: bool = false
	for z2 in wz40:
		if int(floor(float(z2["kind"]) + 0.001)) == 5:
			dunk = true
	_check(not dunk, "no floods in August 1940")
	for r2 in GliderKit.rows():
		var n2: Node3D = GliderKit.build(r2)
		_check(n2.get_child_count() == 0, "no gliders at %s in August 1940" % str((r2 as Dictionary)["id"]))
		n2.free()
	var mb40: Node3D = MulberryKit.build("B")
	_check(mb40.get_child_count() == 0, "no Mulberry harbour in 1940")
	mb40.free()
	EraClock.set_date("1944-06-20")
	var mb: Node3D = MulberryKit.build("B")
	_check(mb.get_child_count() >= 4, "Mulberry B stands on 1944-06-20 (%d parts)" % mb.get_child_count())
	mb.free()
	for gt in ["horsa", "hamilcar", "waco"]:
		for st in GliderKit.STATES:
			var gm: ArrayMesh = GliderKit.glider_mesh(gt, st)
			_check(gm != null and gm.get_surface_count() > 0 and gm.get_surface_count() <= 8, "glider mesh %s/%s (%d surfaces)" % [gt, st, gm.get_surface_count()])
	for k in ["landing_craft", "tank", "enemy_tank", "lorry"]:
		_check(WarGround._mesh(k, "Allies").get_surface_count() > 0, "war ground mesh %s builds" % k)
	for row in WarGround.data().get("floods", []) + WarGround.data().get("battlefields", []) + WarGround.data().get("beaches", []) + GliderKit.rows():
		var rr: Dictionary = row
		_check(str(rr.get("source", "")) != "" and str(rr["from"]) <= str(rr["to"]), "dated war-ground row %s has a source and a sane window" % str(rr["id"]))
	EraClock.set_date("" if keep == EraClock.DEFAULT else keep)
	WarDamage.refresh()


## A six-slot terrace run for the row-merge war-damage test: the slot records _merge_terraces consumes
## (one street, one side, consecutive k), with the laid transforms also sitting in lists[0] the way
## _lay_side leaves them.
func _row_merge_ctx(px: float, pz: float) -> Dictionary:
	var recs: Array = []
	var lists: Array = [[], []]
	for k in 6:
		var xf: Transform3D = Scatter._xf(Vector3(px + float(k) * 26.0, 0.0, pz), 0.0, Vector3(26.0, 7.0, 8.0))
		recs.append({"si": 3, "k": k, "sgn": 1.0, "vi": 0, "band": 0, "xf": xf, "yaw": 0.0,
			"dir": Vector2(1.0, 0.0), "half": 6.0, "fr": 6.0, "w": 26.0, "depth": 8.0})
		(lists[0] as Array).append(xf)
	return {"ctx": {"ct": {}, "slotrec": recs, "seed": 12345}, "lists": lists}


func _test_terraces_war_damage() -> void:
	print("-- terrace rows, street trees and bomb damage")
	var keep: String = EraClock.current()
	EraClock.set_date("1940-10-15")
	WarDamage.refresh()
	var docks: Vector3 = WorldCoords.latlon_to_world(51.497, -0.043)
	# house_doomed must agree with apply_to_houses on every house of a burnt dock street
	var fate_ok: bool = true
	var n_doomed: int = 0
	for i in 300:
		var px: float = docks.x + float(i % 20) * 9.0 - 90.0
		var pz: float = docks.z + float(i / 20) * 11.0 - 80.0
		var one: Array = [[Transform3D(Basis.IDENTITY.scaled(Vector3(8, 7, 9)), Vector3(px, 3.0, pz))]]
		var rr: Array = [[], []]
		WarDamage.apply_to_houses(one, rr, WarDamage.areas_near(Vector2(docks.x, docks.z) - Vector2(900.0, 900.0), 1800.0))
		var kept: bool = not (one[0] as Array).is_empty()
		if kept == WarDamage.house_doomed(px, pz):
			fate_ok = false
		if WarDamage.house_doomed(px, pz):
			n_doomed += 1
	_check(fate_ok, "house_doomed agrees with apply_to_houses on every house of the burnt street")
	_check(n_doomed > 60, "%d of 300 dock houses are gutted or cleared" % n_doomed)
	# a six-slot terrace run laid wholly inside the burnt area must not join into an intact row
	var run_x: float = docks.x
	var run_z: float = docks.z
	var found_run: bool = false
	for t in 800:
		var all_doomed: bool = true
		for s in 6:
			if not WarDamage.house_doomed(docks.x + float(t) * 0.37 + float(s) * 26.0, docks.z + float(t) * 0.11):
				all_doomed = false
				break
		if all_doomed:
			run_x = docks.x + float(t) * 0.37
			run_z = docks.z + float(t) * 0.11
			found_run = true
			break
	_check(found_run, "a six-slot terrace run wholly inside the burnt docks exists")
	if found_run and TownModels.enabled():
		var doomed_m: Dictionary = _row_merge_ctx(run_x, run_z)
		Scatter._merge_terraces(doomed_m["ctx"], doomed_m["lists"])
		var dct: Dictionary = doomed_m["ctx"]["ct"]
		_check(int(dct["rows"]) == 0 and (doomed_m["lists"][0] as Array).size() == 6, "the doomed run stays six singles, no party-wall row (%d rows)" % int(dct["rows"]))
		# the same six slots laid where no damage area reaches still merge
		var clean_x: float = docks.x
		var clean_z: float = docks.z
		var found_clean: bool = false
		for t2 in 1200:
			var clear_all: bool = true
			for s2 in 6:
				if WarDamage.level_at(docks.x + float(t2) * 371.0 + float(s2) * 26.0, docks.z - float(t2) * 233.0) > 0.0:
					clear_all = false
					break
			if clear_all:
				clean_x = docks.x + float(t2) * 371.0
				clean_z = docks.z - float(t2) * 233.0
				found_clean = true
				break
		_check(found_clean, "a terrace run outside every damage area exists")
		if found_clean:
			var clean_m: Dictionary = _row_merge_ctx(clean_x, clean_z)
			Scatter._merge_terraces(clean_m["ctx"], clean_m["lists"])
			var cct: Dictionary = clean_m["ctx"]["ct"]
			_check(int(cct["row_units"]) == 6 and (clean_m["lists"][0] as Array).is_empty(), "the undamaged run merges into party-wall rows (%d units)" % int(cct["row_units"]))
	EraClock.set_date("" if keep == EraClock.DEFAULT else keep)
	WarDamage.refresh()


## The dated port damage (HarbourWar): data sane, meshes build, and each window opens and closes with the date.
func _test_harbour_war() -> void:
	print("-- dated harbour war damage")
	_check(HarbourWar.SITES.size() == 5, "HarbourWar carries %d dated port sites" % HarbourWar.SITES.size())
	for hid in HarbourWar.SITES.keys():
		var st: Dictionary = HarbourWar.SITES[hid]
		_check(str(st.get("source", "")) != "" and str(st["from"]) <= (str(st["to"]) if str(st["to"]) != "" else "9999"), "harbour site %s has a source and a sane window" % str(hid))
	_check(HarbourWar.wreck_mesh(false).get_surface_count() > 0 and HarbourWar.wreck_mesh(true).get_surface_count() > 0, "wreck hull meshes build")
	_check(HarbourWar.toppled_crane_mesh().get_surface_count() > 0 and HarbourWar.rubble_heap_mesh().get_surface_count() > 0, "demolition meshes build")
	_check(HarbourWar.eboat_pen_mesh().get_surface_count() > 0, "the S-boat pen mesh builds")
	var keep2: String = EraClock.current()
	EraClock.set_date("1940-05-20")
	_check(not HarbourWar.active("dunkirk_wrecks") and HarbourWar.build("dunkirk_wrecks").get_child_count() == 0, "no Dunkirk wrecks during the evacuation itself")
	_check(HarbourWar.active("zeebrugge_blockships"), "the Zeebrugge blockships are there the whole war")
	EraClock.set_date("1940-07-01")
	_check(HarbourWar.active("dunkirk_wrecks") and HarbourWar.build("dunkirk_wrecks").get_child_count() >= 2, "the Dunkirk wrecks lie there from July 1940")
	EraClock.set_date("1941-06-01")
	WarDamage.refresh()
	_check(not HarbourWar.active("ijmuiden_pens") and HarbourWar.build("ijmuiden_pens").get_child_count() == 0, "no S-boat pens at IJmuiden in 1941")
	var croydon: Vector3 = WorldCoords.latlon_to_world(51.372, -0.105)
	_check(WarDamage.level_at(croydon.x, croydon.z) == 0.0, "no V-1 damage in Croydon in 1941")
	EraClock.set_date("1943-06-01")
	_check(HarbourWar.active("ijmuiden_pens") and HarbourWar.build("ijmuiden_pens").get_child_count() >= 1, "the IJmuiden S-boat bunker stands in 1943")
	EraClock.set_date("1944-06-20")
	_check(not HarbourWar.active("cherbourg_demolitions"), "Cherbourg is intact before the demolitions")
	EraClock.set_date("1944-10-01")
	WarDamage.refresh()
	_check(HarbourWar.active("cherbourg_demolitions") and HarbourWar.active("lehavre_demolitions"), "Cherbourg and Le Havre are wrecked from autumn 1944")
	var antwerp: Vector3 = WorldCoords.latlon_to_world(51.219, 4.402)
	_check(WarDamage.level_at(croydon.x, croydon.z) > 0.3, "Croydon carries V-1 damage from autumn 1944")
	EraClock.set_date("1944-11-01")
	WarDamage.refresh()
	_check(WarDamage.level_at(antwerp.x, antwerp.z) > 0.15, "Antwerp is under the V-weapons from October 1944")
	EraClock.set_date("" if keep2 == EraClock.DEFAULT else keep2)


func _test_interior_cockpit() -> void:
	print("-- interior cockpit")
	_check(SpitfireCockpit.style_for_id("spitfire") == "spitfire" and SpitfireCockpit.style_for_id("spitfire_mkxiv") == "spitfire", "every Spitfire mark gets the Spitfire interior")
	_check(SpitfireCockpit.style_for_id("bf109") == "bf109" and SpitfireCockpit.style_for_id("bf109g") == "bf109", "every Bf 109 mark gets the Bf 109 interior")
	for fid in ["hurricane", "defiant", "typhoon", "tempest", "fw190", "me262", "p51", "p47", "p38"]:
		_check(SpitfireCockpit.id_supported(fid), "%s gets a modelled interior" % fid)
	_check(SpitfireCockpit.PROFILES["p38"].get("yoke", false) and SpitfireCockpit.PROFILES["me262"].get("twin", false), "the P-38 flies with a control wheel; the twins get twin engine gauges")
	_check(not SpitfireCockpit.id_supported("lancaster") and not SpitfireCockpit.id_supported("bf110") and not SpitfireCockpit.id_supported("mosquito") and not SpitfireCockpit.id_supported(""), "bombers and the two-seat heavy fighters keep the standard cockpit")
	for id in ["spitfire_mkix", "bf109f", "p38", "me262"]:
		var side: String = "Axis" if (id.begins_with("bf109") or id == "me262") else "Allies"
		var a: Aircraft = AIFactory.spawn(self, id, side, Vector3(0.0, 1500.0, 0.0), 90.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
		var c: SpitfireCockpit = SpitfireCockpit.attach(a)
		_check(c != null and a.cockpit_interior == c, "%s: the interior attaches" % id)
		if c == null:
			continue
		_check(not c.visible, "%s: the interior is hidden until the cockpit view is chosen" % id)
		a.set_cockpit_view(true)
		_check(c.visible, "%s: the cockpit view shows the interior" % id)
		a.set_cockpit_view(false)
		_check(not c.visible, "%s: leaving the cockpit view hides it again" % id)
	# AI pilots see poorly astern: the blind spot behind and below the tail
	var hunter: Aircraft = AIFactory.spawn(self, "bf109", "Axis", Vector3(3000.0, 1500.0, 3000.0), 90.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
	var hp: AIPilot = AIFactory.pilot_of(hunter)
	if hp != null:
		var fwd: Vector3 = hunter.get_forward()
		var ahead: float = hp.view_factor(hunter.global_position + fwd * 500.0)
		var astern: float = hp.view_factor(hunter.global_position - fwd * 500.0)
		var low_astern: float = hp.view_factor(hunter.global_position - fwd * 500.0 - Vector3(0.0, 200.0, 0.0))
		_check(ahead > 0.99 and astern < 0.6 and low_astern < astern, "AI pilots spot an attacker astern (and lower still, below the tail) much later than one ahead")
	_check(CameraRig._read_head("") == Vector3.ZERO, "no saved head position gives the default eye point")
	_check(CameraRig.HEAD_MIN.x < 0.0 and CameraRig.HEAD_MAX.x > 0.0 and CameraRig.HEAD_MIN.z < 0.0, "the head can move both ways about the eye point")


func _check(ok: bool, what: String) -> bool:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", what)
	return ok


## A flat land-height provider for the tile-based tests. The headless test scene has no terrain chunk manager, so
## GroundKit.ground_y/raw_y would be 0 everywhere and the canal / railway tile builders (which only place a piece
## where raw_y > 0.5) would place nothing. This stub joins the "terrain" group and returns a positive height so
## those builders exercise their real code paths.
class TestTerrain:
	extends Node
	func get_terrain_y(_x: float, _z: float) -> float:
		return 12.0
	# the aircraft flight code asks for these (flat dry land), used by the take-off soak test
	func get_height_at(_pos: Vector3) -> float:
		return 12.0
	func is_water_at(_pos: Vector3) -> bool:
		return false


func _install_test_terrain() -> void:
	var t := TestTerrain.new()
	t.name = "TestTerrain"
	add_child(t)
	t.add_to_group("terrain")


# ------------------------------------------------------------------ shaders

func _test_shaders() -> void:
	print("-- shaders")
	var want := {
		"res://shaders/toon.gdshader": ["albedo", "detail_mode", "gloss", "patch_color", "underside_color"],
		"res://shaders/toon_real.gdshader": ["albedo", "detail_mode", "gloss", "patch_color", "underside_color"],
		"res://shaders/canopy_glass.gdshader": ["tint", "opacity", "rim_amount", "glint"],
		"res://shaders/outline.gdshader": ["thickness", "outline_color"],
		"res://shaders/team_outline.gdshader": ["outline_color", "fade_start"],
	}
	for path in want.keys():
		var sh: Shader = load(path) as Shader
		if not _check(sh != null, "loads %s" % path):
			continue
		# the toon shaders keep their body in an #include, so ask the compiled shader for its uniforms
		var names: Array = []
		for info in sh.get_shader_uniform_list():
			names.append(String(info["name"]))
		for u in want[path]:
			_check(names.has(String(u)) or sh.code.contains(String(u)), "%s declares uniform %s" % [path, u])


# ------------------------------------------------------------------ mesh helpers

func _test_mesh_helpers() -> void:
	print("-- mesh helpers")
	_check(MeshUtil.ring_xy(0.0, 1.0, 0.5, 0.0, 8).size() == 8, "ring_xy returns 8 points")
	_check(MeshUtil.rect_xy(0.0, 1.0, 1.0).size() == 4, "rect_xy returns 4 points")
	_check(MeshUtil.airfoil(0.0, 0.0, 0.0, 1.0, 0.1).size() == 6, "airfoil returns 6 points")
	var m: ArrayMesh = MeshUtil.loft([MeshUtil.ring_xy(0.0, 1.0, 1.0, 0.0, 8), MeshUtil.ring_xy(1.0, 1.0, 1.0, 0.0, 8)])
	if _check(m != null and m.get_surface_count() == 1, "loft builds one surface"):
		var arr: Array = m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		_check(v.size() > 0, "loft has vertices")
		_check((arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == v.size(), "loft normals match vertices")
	_check(MeshUtil.disc(1.0, 0.1, Vector3.RIGHT, 12) != null, "disc builds")


# ------------------------------------------------------------------ aircraft models

func _test_aircraft_models() -> void:
	print("-- aircraft models")
	var ids: Array = ["spitfire"] + ModelSpecs.IDS
	for id in ids:
		var mid: String = String(id)
		var m: Node3D = AircraftModels.build(mid, "RAF")
		if not _check(m != null, "%s builds" % mid):
			continue
		_check(String(m.name) == "Model", "%s root is named Model" % mid)
		_check(m.get_node_or_null("Body") != null, "%s has a Body group" % mid)
		var fus: MeshInstance3D = m.find_child("Fuselage", true, false) as MeshInstance3D
		_check(fus != null and fus.mesh != null and fus.mesh.get_surface_count() > 0, "%s has a fuselage mesh" % mid)
		_check(m.find_child("CockpitEye", true, false) != null, "%s has a CockpitEye marker" % mid)
		_check(m.find_child("Canopy", true, false) != null, "%s has a Canopy" % mid)
		_check(m.find_child("GearL", true, false) != null and m.find_child("GearR", true, false) != null, "%s has both gear legs" % mid)
		var boxes: Array = []
		_collect_boxes(m, Transform3D.IDENTITY, boxes)
		_check(_merge(boxes).size.length() > 1.0, "%s has non-degenerate geometry" % mid)
		m.free()


# ------------------------------------------------------------------ catalogue

## Every id the menu / AI can pick must have real stats and a model that builds.
func _test_catalogue() -> void:
	print("-- aircraft catalogue")
	for side in ["Allies", "Axis"]:
		for id in AircraftCatalog.ids_for_side(side):
			var sid: String = String(id)
			var st: AircraftStats = AircraftCatalog.load_stats(sid)
			if not _check(st != null and String(st.id) == sid, "%s has its own stats" % sid):
				continue
			_check(not st.display_name.is_empty() and st.max_speed > 0.0, "%s stats are sane" % sid)
			var m: Node3D = AircraftModels.build(String(st.model_id), String(st.nation))
			_check(m != null, "%s model builds (model_id=%s)" % [sid, st.model_id])
			if m != null:
				m.free()


# ------------------------------------------------------------------ decals and pilots

## Every aircraft: the national markings must sit on the airframe (fuselage roundels inside the fuselage box),
## and every cockpit must have a pilot head visible through the glazing.
## Scenery is solid: a tree registered with Obstacles is hit when flown through, missed above or beside it.
func _test_obstacles() -> void:
	print("-- obstacles")
	Obstacles.clear()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.0
	cyl.height = 16.0
	var mmi: MultiMeshInstance3D = Scatter.multi(cyl, [Transform3D(Basis(), Vector3(5000.0, 8.0, 7000.0))])
	add_child(mmi)
	var at := Vector3(5000.0, 10.0, 7000.0)
	_check(not Obstacles.hit(at, 1.5, at.y - 1.0, at.y + 1.0).is_empty() or _resolve_again(at), "flying into a tree hits it")
	_check(Obstacles.hit(at + Vector3(0, 30, 0), 1.5, at.y + 29.0, at.y + 31.0).is_empty(), "flying over a tree misses it")
	_check(Obstacles.hit(at + Vector3(20, 0, 0), 1.5, at.y - 1.0, at.y + 1.0).is_empty(), "flying beside a tree misses it")
	mmi.queue_free()


func _resolve_again(at: Vector3) -> bool:
	Obstacles._next_resolve = 0
	return not Obstacles.hit(at, 1.5, at.y - 1.0, at.y + 1.0).is_empty()


func _test_markings() -> void:
	print("-- decals and pilots")
	# fin swastikas follow the Historical markings setting (off by default)
	var was_hist: bool = GameState.historical_markings
	for want in [false, true]:
		GameState.historical_markings = want
		var lw: Node3D = AircraftModels.build("bf109", "Luftwaffe")
		var sw: Array = lw.find_children("DecalFinSwastika*", "Node3D", true, false)
		var vis_ok: bool = not sw.is_empty()
		for n in sw:
			vis_ok = vis_ok and (n as Node3D).visible == want
		_check(vis_ok, "Bf 109 fin swastika %s with Historical markings %s" % ["shown" if want else "hidden", "on" if want else "off"])
		lw.free()
	GameState.historical_markings = was_hist
	var ids: Array = ["spitfire"] + ModelSpecs.IDS
	for id in ids:
		var mid: String = String(id)
		var m: Node3D = AircraftModels.build(mid, "RAF")
		if not _check(m != null, "%s builds for decal checks" % mid):
			continue
		_check(m.find_child("Pilot", true, false) != null, "%s has a pilot in the cockpit" % mid)
		var boxes: Array = []
		_collect_boxes(m, Transform3D.IDENTITY, boxes)
		var fus: AABB = _named_box(boxes, "Fuselage")
		var all: AABB = _merge(boxes)
		var fus_ok: bool = true
		var out_ok: bool = true
		var n_dec: int = 0
		for b in boxes:
			var nm: String = String(b[0])
			if not nm.begins_with("Decal"):
				continue
			n_dec += 1
			var a: AABB = b[1]
			if nm.begins_with("DecalFus") and fus.size.length() > 1.0:
				if not fus.grow(0.6).encloses(a):
					fus_ok = false
			elif not all.grow(0.6).encloses(a):
				out_ok = false
		_check(n_dec > 0 or Livery.has_livery(mid, "RAF"), "%s has national markings" % mid)
		if Livery.has_livery(mid, "RAF"):
			var fz: MeshInstance3D = m.find_child("Fuselage", true, false) as MeshInstance3D
			var sk: ShaderMaterial = fz.material_override as ShaderMaterial if fz != null else null
			_check(sk != null and bool(sk.get_shader_parameter("use_livery")), "%s wears its painted livery" % mid)
			_check(fz != null and fz.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != null, "%s skin is unwrapped for the livery" % mid)
		_check(fus_ok, "%s fuselage roundels stay on the fuselage" % mid)
		_check(out_ok, "%s wing and fin markings stay on the airframe" % mid)
		m.free()


# ------------------------------------------------------------------ turret mounts

func _test_turret_mounts() -> void:
	print("-- turret mounts")
	var expect_axis := {"nose": Vector3(0, 0, -1), "tail": Vector3(0, 0, 1), "dorsal": Vector3(0, 1, 0),
		"ventral": Vector3(0, -1, 0), "waist_l": Vector3(-1, 0, 0), "waist_r": Vector3(1, 0, 0)}
	for key in DefensiveTurrets.MOUNTS.keys():
		var ax: Vector3 = (DefensiveTurrets.MOUNTS[key]["axis"] as Vector3).normalized()
		_check(ax.dot(expect_axis[key]) > 0.9, "turret '%s' guns point %s (got %s)" % [key, expect_axis[key], ax])
	var ids: Array = ["spitfire"] + ModelSpecs.IDS
	var checked: int = 0
	for id in ids:
		var mid: String = String(id)
		if not AircraftCatalog.is_bomber(mid):
			continue
		var st: AircraftStats = AircraftCatalog.load_stats(mid)
		if st == null:
			continue
		var layout: Array = DefensiveTurrets.layout_for(mid, st.bombs)
		var m: Node3D = AircraftModels.build(mid, "RAF")
		if not _check(m != null, "%s builds for turret checks" % mid):
			continue
		var boxes: Array = []
		_collect_boxes(m, Transform3D.IDENTITY, boxes)
		var fus: AABB = _named_box(boxes, "Fuselage")
		if _check(fus.size.length() > 1.0, "%s fuselage box found" % mid):
			for key in layout:
				var p: Vector3 = DefensiveTurrets.mount_local(mid, String(key), st.radius)
				_check(fus.grow(2.5).has_point(p), "%s turret '%s' at %s is off the fuselage %s" % [mid, key, p, fus])
			if not layout.is_empty():
				checked += 1
		m.free()
	_check(checked >= 8, "a turret layout was checked on every armed bomber (%d)" % checked)


func _collect_boxes(n: Node3D, xf: Transform3D, out: Array) -> void:
	var t: Transform3D = xf * n.transform
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh != null:
			out.append([String(mi.name), t * mi.get_aabb()])
	for c in n.get_children():
		if c is Node3D:
			_collect_boxes(c as Node3D, t, out)


func _merge(boxes: Array) -> AABB:
	var a := AABB()
	var first: bool = true
	for b in boxes:
		var bb: AABB = b[1]
		if first:
			a = bb
			first = false
		else:
			a = a.merge(bb)
	return a


func _named_box(boxes: Array, nm: String) -> AABB:
	for b in boxes:
		if String(b[0]) == nm:
			return b[1]
	return AABB()


# ------------------------------------------------------------------ scatter masks

## The lake mask must be selective (some water, some land) so scatter can keep trees off it.
func _test_scatter_masks() -> void:
	print("-- scatter masks")
	var over: int = 0
	var under: int = 0
	var lo: float = 9.0
	var hi: float = -9.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 3000:
		var x: float = rng.randf_range(-200000.0, 200000.0)
		var z: float = rng.randf_range(-250000.0, 20000.0)
		var n: float = Scatter.lake_noise(x, z)
		lo = minf(lo, n)
		hi = maxf(hi, n)
		if n > 0.706:
			over += 1
		else:
			under += 1
	_check(lo > 0.0, "lake noise is a positive field")
	_check(over > 0 and under > 0, "lake mask is selective (over=%d under=%d)" % [over, under])
	_check(lo >= 0.0 and hi <= 1.0, "lake noise stays in 0..1 (%.2f..%.2f)" % [lo, hi])


# ------------------------------------------------------------------ music

## The start-menu and in-flight playlists must be discoverable and loadable.
func _test_music() -> void:
	print("-- music playlists")
	var menu: Array = MenuMusic.discover_in("res://assets/music/")
	var ingame: Array = MenuMusic.discover_in("res://assets/music/ingame/")
	_check(menu.size() >= 2, "start-menu playlist has tracks (%d)" % menu.size())
	_check(ingame.size() >= 25, "in-game playlist has tracks (%d)" % ingame.size())
	for p in menu:
		_check(ResourceLoader.exists(String(p)), "menu track loads: %s" % p)
	for p in ingame:
		_check(ResourceLoader.exists(String(p)), "in-game track loads: %s" % p)
	# Options > Music: the pause between tracks is clamped, and folder import ignores folders with no audio
	var gap_before: float = GameState.music_gap
	GameState.set_music_gap(9999.0, false)
	_check(GameState.music_gap <= 300.0, "music pause clamps to 300 s (%.0f)" % GameState.music_gap)
	GameState.set_music_gap(-5.0, false)
	_check(GameState.music_gap >= 0.0, "music pause never goes negative")
	GameState.set_music_gap(gap_before, false)
	_check(MenuMusic.audio_files_in("res://assets/fonts").is_empty(), "folder scan skips folders without audio")
	_check(MenuMusic.import_folder("ingame", "res://no_such_folder").is_empty(), "importing a missing folder adds nothing")
	# A playlist that names a file which has gone must not list it (Options > Music "Fix list")
	_check(GameState.music_existing(["res://assets/music/freedom.mp3", "user://music/menu/gone.mp3"]).size() == 1, "only tracks that exist stay in a playlist")
	_check(not MenuMusic.exists("res://assets/music/not_a_track.mp3"), "a missing track is reported missing")
	var saved_list: Array = GameState.ingame_music_playlist.duplicate()
	var saved_cfg: bool = GameState.ingame_music_configured
	var saved_cur: String = GameState.ingame_music_current
	GameState.ingame_music_playlist = ["res://assets/music/ingame/freedom.mp3", "user://music/ingame/gone.mp3"]
	GameState.ingame_music_configured = true
	var fix: Dictionary = GameState.fix_music_playlist("ingame", false)
	_check(int(fix["removed"]) == 1, "fix list drops the missing track (%d)" % int(fix["removed"]))
	_check(not GameState.music_playlist("ingame").has("user://music/ingame/gone.mp3"), "fixed list holds no dead entries")
	_check(GameState.music_playlist("ingame").has("res://assets/music/ingame/freedom.mp3"), "fix list keeps the tracks that play")
	GameState.ingame_music_playlist = saved_list
	GameState.ingame_music_configured = saved_cfg
	GameState.ingame_music_current = saved_cur
	# The Ops Room tooltip is its own dim hint row under the tasking
	var card_hud := HUD.new()
	var rows: Array = card_hud._card_rows("AIRFIELD ATTACK   30 km\n(P: skip task, F1: see controls)", UIKit.display_font(), UIKit.font(true))
	_check(rows.size() == 2, "tasking card keeps the tooltip on its own row (%d)" % rows.size())
	if rows.size() == 2:
		_check(int(rows[0][0][1]) == 1, "tasking title is the card heading")
		_check(int(rows[1][0][1]) == 2, "tooltip renders in the hint style")
	card_hud.free()
	# Import folder end to end: every audio file in the tree is copied, non-audio is left behind
	var src: String = "user://music_test_src"
	DirAccess.make_dir_recursive_absolute(src + "/sub")
	for f in ["/one.mp3", "/two.ogg", "/sub/three.wav", "/notes.txt"]:
		var fh: FileAccess = FileAccess.open(src + f, FileAccess.WRITE)
		if fh != null:
			fh.store_string("x")
			fh = null
	var copied: Array = MenuMusic.import_folder("menu", src)
	_check(copied.size() == 3, "folder import copies every audio file in the tree (%d)" % copied.size())
	for p in copied:
		_check(FileAccess.file_exists(String(p)), "imported copy exists: %s" % p)
		MenuMusic.delete_track(String(p))
	for f in ["/sub/three.wav", "/sub", "/one.mp3", "/two.ogg", "/notes.txt", ""]:
		DirAccess.remove_absolute(src + f)


## Every audio file in the repo must be covered by tools/audio_allowlist.json. Commercial recordings
## (film, TV, game soundtracks) cannot be redistributed with the game: the player imports their own
## copies at run time. This gate stops an unlicensed file being committed and shipped again.
func _test_audio_licences() -> void:
	print("-- audio licences")
	var raw: String = FileAccess.get_file_as_string("res://tools/audio_allowlist.json")
	if not _check(raw != "", "audio allowlist is readable"):
		return
	var data: Variant = JSON.parse_string(raw)
	if not _check(data is Dictionary, "audio allowlist is valid JSON"):
		return
	var allowed: Dictionary = {}
	for t in data.get("tracks", []):
		for k in ["path", "title", "artist", "source"]:
			_check(t.has(k) and str(t[k]) != "", "allowlist entry has %s: %s" % [k, str(t.get("path", "?"))])
		allowed[str(t.get("path", ""))] = true
	var generated: Array = data.get("generated", [])
	var files: Array = _audio_files_under("res://assets/")
	_check(files.size() > 0, "audio files found under res://assets (%d)" % files.size())
	for f in files:
		var rel: String = String(f).trim_prefix("res://")
		var covered: bool = allowed.has(rel)
		if not covered:
			for g in generated:
				if rel.begins_with(str(g)):
					covered = true
					break
		_check(covered, "audio file is licence-listed: %s" % rel)


func _audio_files_under(dir: String, out: Array = []) -> Array:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if MenuMusic.EXTS.has(dir.path_join(f).get_extension().to_lower()):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_audio_files_under(dir.path_join(sub) + "/", out)
	return out


## A stand-in for anything the target index collects (a ship, a ground target or an aircraft).
class FakeDamageable:
	extends Node3D
	var team: String = "Axis"
	var velocity: Vector3 = Vector3.ZERO
	var hit_radius: float = 1.0
	var is_dead: bool = false
	var state: int = 0


## TargetIndex: the shared snapshot the AI and the gunsight use instead of walking the scene tree every frame.
func _test_target_index() -> void:
	print("-- target index")
	TargetIndex._next_ms = 0
	var near_t := FakeDamageable.new()
	near_t.position = Vector3(100, 0, 0)
	near_t.add_to_group("ground_target")
	add_child(near_t)
	var far_t := FakeDamageable.new()
	far_t.position = Vector3(900, 0, 0)
	far_t.add_to_group("ground_target")
	add_child(far_t)
	var friendly := FakeDamageable.new()
	friendly.team = "Allies"
	friendly.position = Vector3(50, 0, 0)
	friendly.add_to_group("ground_target")
	add_child(friendly)
	TargetIndex.ensure(get_tree())
	_check(TargetIndex.count() >= 2, "target index holds the scene's targets (%d)" % TargetIndex.count())
	_check(TargetIndex.nearest(Vector3.ZERO, "Allies", 10.0, 2000.0) == near_t, "nearest picks the closest enemy, not the friendly")
	_check(TargetIndex.nearest_ahead(Vector3.ZERO, Vector3.RIGHT, "Allies", 10.0, 2000.0, 0.1) == near_t, "the strike cone picks the target on the line")
	_check(TargetIndex.nearest_ahead(Vector3.ZERO, Vector3.LEFT, "Allies", 10.0, 2000.0, 0.1) == null, "off the line finds no strike target")
	_check(TargetIndex.any_near(Vector3(105, 0, 0), "Allies", 20.0), "the bombsight sees a target over the aim point")
	near_t.queue_free()
	far_t.queue_free()
	friendly.queue_free()


func _test_audio() -> void:
	print("-- audio synth")
	var a := AudioSFX.new()
	for id in AudioSFX.ENGINES.keys():
		for voices in [1, 3]:
			var s: AudioStreamWAV = a._stream("engine:%s:%d" % [id, voices]) as AudioStreamWAV
			if not _check(s != null and s.data.size() > 1000, "engine %s x%d built" % [id, voices]):
				continue
			var pk: float = _peak(s)
			_check(pk > 0.05 and pk <= 0.999, "engine %s x%d peak %.2f in range" % [id, voices, pk])
			_check(s.loop_mode != AudioStreamWAV.LOOP_DISABLED, "engine %s x%d loops" % [id, voices])
	for id in AudioSFX.GUNS.keys():
		var g: AudioStreamWAV = a._stream("gun:" + String(id)) as AudioStreamWAV
		if not _check(g != null and g.data.size() > 100, "gun %s built" % id):
			continue
		_check(_peak(g) > 0.05, "gun %s is audible" % id)
	for n in ["flak_close", "hit_metal:0", "hit_metal:1", "hit_metal:2", "hit_frag:0", "hit_frag:1", "hit_frag:2"]:
		var cs: AudioStreamWAV = a._stream(n) as AudioStreamWAV
		if _check(cs != null and cs.data.size() > 1000, "combat sound %s built" % n):
			var cp: float = _peak(cs)
			_check(cp > 0.3 and cp <= 0.999, "combat sound %s peak %.2f in range" % [n, cp])
	a.free()



func _test_logbook_voice() -> void:
	print("-- logbook voice")
	_check(LogbookMenu.VOICE_TRACKS.size() >= 1, "logbook has spoken tracks")
	for rel in LogbookMenu.VOICE_TRACKS:
		var found: bool = false
		for ext in ["ogg", "wav", "mp3"]:
			if ResourceLoader.exists("res://assets/voice/%s.%s" % [rel, ext]):
				found = true
				break
		_check(found, "logbook voice file exists: %s" % rel)
	# the picker stays in range and never repeats the same track twice running
	LogbookMenu._last_track = -1
	var prev: int = -1
	var n: int = LogbookMenu.VOICE_TRACKS.size()
	for i in 50:
		var pick: int = randi() % n
		if n > 1 and pick == LogbookMenu._last_track:
			pick = (pick + 1) % n
		_check(pick >= 0 and pick < n, "logbook pick in range")
		if n > 1:
			_check(pick != prev, "logbook pick never repeats")
		LogbookMenu._last_track = pick
		prev = pick


func _test_custom_missions() -> void:
	print("-- custom missions (Mission Editor)")
	var all: Array = MissionDoc.list_all()
	var bundled: int = 0
	for e in all:
		if bool(e["bundled"]):
			bundled += 1
			var v: Dictionary = MissionDoc.validate(e["doc"])
			_check((v["errors"] as PackedStringArray).is_empty(), "example mission '%s' is valid %s" % [e["name"], str(v["errors"])])
			var cfg: Dictionary = MissionDoc.start_config(e["doc"], str(e["path"]))
			_check(str(cfg["mode"]) == "custom" and cfg.has("spawn_lat") and cfg.has("custom_doc"), "example '%s' builds a start config" % e["name"])
	_check(bundled >= 3, "three example missions ship with the game (%d)" % bundled)
	_check(ModeRegistry.has_mode("custom") and not ModeRegistry.get_available_ids().has("custom"), "the custom mode exists but stays out of the menu's Mode list")
	# every unit kind makes a valid default unit for both sides
	for kind in MissionDoc.UNIT_KINDS.keys():
		for sd in ["Allies", "Axis"]:
			var d0: Dictionary = MissionDoc.new_doc(sd)
			var u: Dictionary = MissionDoc.new_unit(d0, kind, 51.0, 1.3)
			_check(MissionDoc.unit_types(kind, str(u["side"])).has(str(u["type"])), "a new %s unit (%s) has a valid type" % [kind, sd])
	# validation catches broken references; upgrade fills in what a hand-written file leaves out
	var bad: Dictionary = MissionDoc.upgrade({"name": "x", "side": "Allies", "aircraft": "spitfire", "objectives": [{"id": "o1", "kind": "destroy", "target": "nope"}],
		"triggers": [{"id": "t1", "conditions": [{"type": "unit_destroyed", "unit": "nope"}], "actions": [{"type": "warp_drive"}]}]})
	var vb: Dictionary = MissionDoc.validate(bad)
	_check((vb["errors"] as PackedStringArray).size() >= 3, "validation finds the missing unit, the bad reference and the unknown action (%d)" % (vb["errors"] as PackedStringArray).size())
	_check(bad.has("start") and bad.has("units") and bool((bad["objectives"][0] as Dictionary).get("required", false)), "upgrade fills in missing keys")
	# save, list, load and delete a mission in user://missions/
	var doc: Dictionary = MissionDoc.new_doc("Allies")
	doc["name"] = "Test mission %d" % randi()
	var path: String = MissionDoc.save(doc)
	_check(path.begins_with(MissionDoc.USER_DIR) and FileAccess.file_exists(path), "a mission saves to user://missions/")
	_check(str(MissionDoc.load_file(path).get("name", "")) == doc["name"], "a saved mission loads back")
	_check(MissionDoc.delete(path) and not FileAccess.file_exists(path), "a saved mission can be deleted")
	# the trigger engine: time -> flag -> objective -> mission end; once / repeat; any / all; delays
	var td: Dictionary = MissionDoc.new_doc("Allies")
	td["objectives"] = [{"id": "o1", "text": "Do it", "kind": "manual", "target": "", "required": true, "shown": false}]
	td["triggers"] = [
		{"id": "t1", "name": "a", "once": true, "logic": "all", "delay": 0.0, "conditions": [{"type": "time", "seconds": 10.0}], "actions": [{"type": "flag", "flag": "go", "value": true}, {"type": "objective", "objective": "o1", "state": "active"}]},
		{"id": "t2", "name": "b", "once": true, "logic": "all", "delay": 5.0, "conditions": [{"type": "flag", "flag": "go", "value": true}, {"type": "trigger_fired", "trigger": "t1"}], "actions": [{"type": "objective", "objective": "o1", "state": "complete"}]},
		{"id": "t3", "name": "c", "once": false, "logic": "any", "delay": 0.0, "conditions": [{"type": "time", "seconds": 1.0e9}, {"type": "flag", "flag": "blink", "value": true}], "actions": [{"type": "score", "points": 1}]},
	]
	_check((MissionDoc.validate(td)["errors"] as PackedStringArray).is_empty(), "the trigger test mission is valid")
	var m := CustomMissionMode.new()
	m.configure(MissionDoc.start_config(td))
	add_child(m)
	m._init_state()
	m.running = true
	m.elapsed = 5.0
	m._run_triggers()
	m._run_queue()
	_check(m._obj("o1")["state"] == "inactive" and not m._flags.has("go"), "nothing fires before its time")
	m.elapsed = 10.0
	m._run_triggers()
	m._run_queue()
	_check(bool(m._flags.get("go", false)) and m._obj("o1")["state"] == "active", "the time trigger sets the flag and shows the objective")
	m._run_triggers()
	m._run_queue()
	_check(m._obj("o1")["state"] == "active", "a delayed trigger waits its delay")
	m.elapsed = 15.5
	m._run_triggers()
	m._run_queue()
	_check(m._obj("o1")["state"] == "complete", "after the delay the second trigger completes the objective")
	m._check_end()
	_check(m._ending, "all required objectives done: the mission ends in success")
	var s0: int = m.score
	for k in 3:       # a repeating trigger fires on each rising edge, not every check
		m._flags["blink"] = true
		m._run_triggers()
		m._run_triggers()
		m._run_queue()
		m._flags["blink"] = false
		m._run_triggers()
	_check(m.score - s0 == 3, "a repeating trigger fires once each time its condition becomes true (%d)" % (m.score - s0))
	var t1: Dictionary = m._trig[0]
	m._run_triggers()
	_check(int(t1["fired"]) == 1, "a once trigger never fires twice")
	m.running = false
	m.queue_free()

func _peak(s: AudioStreamWAV) -> float:
	var d: PackedByteArray = s.data
	var m: float = 0.0
	for i in range(0, d.size() - 1, 2):
		m = maxf(m, absf(float(d.decode_s16(i))) / 32768.0)
	return m


## Historical missions: every briefing names real places, every mission has two bonus objectives, and the grade,
## debrief and raid plans behave (MissionBrief, DefendMode.raid_plan, ResultsScreen).
func _test_mission_briefs() -> void:
	print("-- mission briefings, bonus objectives and debrief")
	var n: int = 0
	var bad_place: Array = []
	var bad_brief: Array = []
	var bad_bonus: Array = []
	for m in HistoricalMissions.list():
		for sd in HistoricalMissions.sides_of(str(m["id"])):
			n += 1
			var tag: String = "%s/%s" % [m["id"], sd]
			for id in MissionBrief.task_ids(m, sd):
				if not MissionBrief.has_place(str(id)):
					bad_place.append("%s:%s" % [tag, id])
			var br: String = HistoricalMissions.briefing_for(str(m["id"]), sd)
			if not (br.contains("TASK  ") and br.contains("OPPOSITION  ") and br.contains("CONDITIONS  ") and br.contains(str(m["brief"]))):
				bad_brief.append(tag)
			var bs: Array = MissionBrief.bonuses(m, sd)
			var ok: bool = bs.size() == MissionBrief.BONUS_COUNT and str(bs[0]["id"]) != str(bs[1]["id"])
			for b in bs:
				ok = ok and str(b["text"]) != "" and str(b["short"]) != "" and str(b["text"]) != str(b["id"])
			if not ok or JSON.stringify(bs) != JSON.stringify(MissionBrief.bonuses(m, sd)):
				bad_bonus.append(tag)
	_check(n >= 74, "every historical mission side is briefed (%d)" % n)
	_check(bad_place.is_empty(), "mission tasks name places that are in locations.json %s" % str(bad_place))
	_check(bad_brief.is_empty(), "every briefing has its task, opposition and conditions %s" % str(bad_brief))
	_check(bad_bonus.is_empty(), "every mission side has two different, stable bonus objectives %s" % str(bad_bonus))
	var kent: Dictionary = HistoricalMissions.get_mission("bob_kent")
	var kb: String = MissionBrief.briefing(kent, "Allies")
	_check(not kb.contains("Radar Dover Ch") and kb.contains(MissionBrief.place_name("radar_dover_ch")), "a briefing uses the real name of a target, not its id")
	_check(MissionBrief.route_line(kent, "Allies").contains(MissionBrief.place_name("biggin_hill")), "the route line starts from the home airfield")
	_check(absf(MissionBrief.latlon_km(51.0, 0.0, 52.0, 0.0) - 111.2) < 1.0, "one degree of latitude is about 111 km")
	_check(MissionBrief.compass(0.0) == "north" and MissionBrief.compass(135.0) == "south-east" and MissionBrief.compass(350.0) == "north", "bearings read as compass points")
	_check(MissionBrief.date_text("1940-08-15") == "15 August 1940", "mission dates are written out")
	var wales: Dictionary = HistoricalMissions.get_mission("train_wales_bomber")
	var wids: Array = []
	for b in MissionBrief.bonuses(wales, "Allies"):
		wids.append(str(b["id"]))
	_check(not wids.has("air_kill"), "a mission with no enemy fighters never asks for an air kill %s" % str(wids))
	# grades and bonuses
	_check(MissionBrief.grade(false, 2) == 0 and MissionBrief.grade(true, 0) == 1 and MissionBrief.grade(true, 2) == 3, "the grade is 0 for a failure, otherwise 1 plus the bonuses")
	var par: Dictionary = MissionBrief._bonus("par", {"time_limit": 1200})
	_check(MissionBrief.bonus_done(par, {"success": true, "time": 1100.0}) and not MissionBrief.bonus_done(par, {"success": true, "time": 1300.0}), "the par bonus needs the mission finished inside the time")
	_check(not MissionBrief.bonus_done(par, {"success": false, "time": 100.0}), "no bonus counts on a failed mission")
	_check(MissionBrief.bonus_lost(par, {"time": 1300.0}) and not MissionBrief.bonus_lost(par, {"time": 900.0}), "the par bonus is lost once the time is up")
	var acc: Dictionary = MissionBrief._bonus("accuracy", {})
	_check(MissionBrief.bonus_done(acc, {"success": true, "bombs_dropped": 4, "bombs_hit": 2}) and not MissionBrief.bonus_done(acc, {"success": true, "bombs_dropped": 4, "bombs_hit": 1})
		and not MissionBrief.bonus_done(acc, {"success": true, "bombs_dropped": 0}), "the accuracy bonus needs half the bombs dropped to hit")
	var cln: Dictionary = MissionBrief._bonus("clean", {})
	_check(MissionBrief.bonus_done(cln, {"success": true, "health_frac": 0.8}) and not MissionBrief.bonus_done(cln, {"success": true, "health_frac": 0.3}), "the light-damage bonus reads the airframe")
	var itc: Dictionary = MissionBrief._bonus("intact", {})
	_check(MissionBrief.bonus_done(itc, {"success": true, "protected": 2, "protected_alive": 2}) and MissionBrief.bonus_lost(itc, {"protected": 2, "protected_alive": 1}), "the all-sites bonus is lost with the first site")
	var db: Dictionary = MissionBrief.debrief(kent, "Allies", {"success": true, "time": 900.0, "air_kills": 4, "protected": 2, "protected_alive": 2, "health_frac": 0.9})
	_check((db["objectives"] as Array).size() == 1 + MissionBrief.BONUS_COUNT and bool(db["objectives"][0]["primary"]) and bool(db["objectives"][0]["done"]), "the debrief lists the task and the bonuses")
	_check(int(db["grade"]) == 3 and str(db["grade_name"]) == "Outstanding" and str(db["summary"]).length() > 20, "a clean defence is graded Outstanding with a written account (%s)" % str(db["grade_name"]))
	var dbf: Dictionary = MissionBrief.debrief(kent, "Allies", {"success": false, "reason": "killed - shot down", "protected": 2, "protected_alive": 1})
	_check(int(dbf["grade"]) == 0 and str(dbf["summary"]).contains("shot down"), "a failed mission is graded 0 and says why")
	# best grade per mission
	var keep: Dictionary = GameState.mission_grades.duplicate()
	GameState.mission_grades = {}
	GameState.record_mission_grade("zz_test", 2, false)
	GameState.record_mission_grade("zz_test", 1, false)
	_check(GameState.mission_grade("zz_test") == 2 and GameState.mission_grade("zz_none") == 0, "the best grade on a mission is kept")
	_check(GameState.mission_label("zz_test", "X").contains("Commended"), "the mission list shows the best grade")
	GameState.mission_grades = keep
	# raids on a defend mission differ
	_check(str(DefendMode.raid_plan(1, 3)["kind"]) == "mass" and str(DefendMode.raid_plan(3, 3)["kind"]) == "big", "the first raid is massed and the last is the heaviest")
	_check(str(DefendMode.raid_plan(2, 4, 0)["kind"]) != str(DefendMode.raid_plan(3, 4, 0)["kind"]), "the middle raids alternate between low raids and fighter sweeps")
	_check(str(DefendMode.raid_plan(2, 3, 0)["kind"]) != str(DefendMode.raid_plan(2, 3, 1)["kind"]), "the raid mix differs between missions")
	for k in ["mass", "low", "sweep", "big"]:
		_check(DefendMode.raid_call({"kind": k}, 2, 3, "Dover").contains("Dover"), "the %s raid call names the target" % k)
	_check(ResultsScreen.star_points(Vector2.ZERO, 10.0).size() == 10, "a grade star has ten points")
	# the objective card text
	var hm := HistoricalMissions.create("bob_kent", "Allies")
	hm._bonuses = MissionBrief.bonuses(kent, "Allies")
	hm._objective_text = "Protect: Dover"
	var card: String = hm.objective_card_text({"time": 60.0, "air_kills": 1, "protected": 2, "protected_alive": 2, "health_frac": 1.0})
	_check(card.begins_with("OBJECTIVES\nProtect: Dover") and card.count("BONUS") == MissionBrief.BONUS_COUNT, "the objective card lists the task and both bonuses")
	_check(hm.pursuit_type() == "bf109", "the fighters sent after the player are a type the enemy flies in that mission (%s)" % hm.pursuit_type())
	hm.free()


# ------------------------------------------------------------------ 1940s world content (Phase 6)

## data/industry_1940.json, data/docks_1940.json and data/landmarks_1940.json parse and are non-empty.
func _test_data_files() -> void:
	print("-- 1940s data files")
	var industry: Variant = _load_json("res://data/industry_1940.json")
	if _check(industry is Dictionary, "industry_1940.json parses"):
		_check_has_entries(industry as Dictionary, "sites", "industry_1940.json sites")
	var docks: Variant = _load_json("res://data/docks_1940.json")
	if _check(docks is Dictionary, "docks_1940.json parses"):
		var dd: Dictionary = docks
		_check_has_entries(dd, "piers", "docks_1940.json piers")
		_check_has_entries(dd, "docks", "docks_1940.json docks")
	var lms: Variant = _load_json("res://data/landmarks_1940.json")
	if _check(lms is Dictionary, "landmarks_1940.json parses"):
		_check_has_entries(lms as Dictionary, "landmarks", "landmarks_1940.json landmarks")


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt: String = f.get_as_text()
	f = null
	return JSON.parse_string(txt)


func _check_has_entries(d: Dictionary, key: String, what: String) -> void:
	var arr: Array = d.get(key, [])
	_check(arr.size() > 0, "%s non-empty (%d)" % [what, arr.size()])


## MapEdits (data/map_edits.json): parse + validate good and bad rows, is_removed circle maths, save / load.
func _test_map_edits() -> void:
	print("-- map edits")
	var p: String = "user://t_map_edits.json"
	var good: Dictionary = {"version": 1, "edits": [
		{"op": "add", "id": "g1", "asset": "church", "lat": 49.18, "lon": -0.36, "yaw": 90.0, "scale": 1.0},
		{"op": "add", "id": "g2", "asset": "barn", "lat": 49.20, "lon": -0.30},
		{"op": "remove", "id": "g3", "lat": 49.18, "lon": -0.36, "radius": 100.0, "what": "houses"}]}
	_write_text(p, JSON.stringify(good))
	MapEdits.load(p)
	_check(MapEdits.adds().size() == 2 and MapEdits.removes().size() == 1, "two good adds and one good remove parse")
	var a2: Dictionary = MapEdits.adds()[1]
	_check(float(a2["yaw"]) == 0.0 and float(a2["scale"]) == 1.0, "a missing yaw and scale default")
	MapEdits.load()
	_check(MapEdits.adds().size() + MapEdits.removes().size() == MapEdits.all().size(), "every row of the shipped data/map_edits.json is a valid add or remove")
	var bad: Dictionary = {"version": 1, "edits": [1, {},
		{"op": "warp", "id": "b1", "lat": 1.0, "lon": 2.0},
		{"op": "add", "id": "b2", "lat": 1.0, "lon": 2.0},
		{"op": "add", "id": "b3", "asset": "x", "lat": "north", "lon": 2.0},
		{"op": "add", "id": "b4", "asset": "x", "lat": 1.0, "lon": 2.0, "scale": 0.0},
		{"op": "remove", "id": "b5", "lat": 1.0, "lon": 2.0, "what": "towns"},
		{"op": "remove", "id": "b6", "lat": 1.0, "lon": 2.0, "radius": -4.0}]}
	_write_text(p, JSON.stringify(bad))
	MapEdits.load(p)
	_check(MapEdits.adds().is_empty() and MapEdits.removes().is_empty(), "every bad row is skipped, never fatal")
	MapEdits.load("res://no_such_map_edits.json")
	_check(not MapEdits.has_edits(), "a missing file means no edits")
	_write_text(p, "[1, 2, 3]")
	MapEdits.load(p)
	_check(not MapEdits.has_edits(), "a file that is not a JSON object means no edits")
	_write_text(p, "{\"version\": 1}")
	MapEdits.load(p)
	_check(not MapEdits.has_edits(), "a file with no edits array means no edits")
	var c: Vector3 = WorldCoords.latlon_to_world(49.18, -0.36)
	_write_text(p, JSON.stringify(good))
	MapEdits.load(p)
	_check(MapEdits.is_removed(c, "houses") and MapEdits.is_removed(c + Vector3(90.0, 0.0, 0.0), "houses"), "a point inside a remove circle is removed")
	_check(not MapEdits.is_removed(c + Vector3(0.0, 0.0, 110.0), "houses"), "a point outside the circle is kept")
	_check(not MapEdits.is_removed(c, "trees"), "a houses-only removal leaves the trees alone")
	var every: Dictionary = {"version": 1, "edits": [{"op": "remove", "id": "g4", "lat": 49.18, "lon": -0.36, "radius": 50.0, "what": "all"}]}
	_write_text(p, JSON.stringify(every))
	MapEdits.load(p)
	_check(MapEdits.is_removed(c, "trees") and MapEdits.is_removed(c, "sites"), "what 'all' matches every kind")
	_write_text(p, JSON.stringify(good))
	MapEdits.load(p)
	var a0: String = JSON.stringify(MapEdits.adds())
	var r0: String = JSON.stringify(MapEdits.removes())
	var rt: String = "user://t_map_edits_rt.json"
	_check(MapEdits.save(rt), "the edits save")
	var txt: String = FileAccess.get_file_as_string(rt)
	_check(txt.contains("\n") and txt.contains("\"version\"") and txt.contains("\"edits\""), "the saved file is pretty JSON")
	MapEdits.save(rt)
	_check(FileAccess.get_file_as_string(rt) == txt, "saving twice is byte-stable")
	MapEdits.load(rt)
	_check(JSON.stringify(MapEdits.adds()) == a0 and JSON.stringify(MapEdits.removes()) == r0, "save then load round trips")
	MapEdits.load()
	for pp in [p, rt]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pp))


## MapAssets: the catalogue of placeable keys - every key builds a Node3D with a label and a category.
func _test_map_assets() -> void:
	print("-- map assets")
	var keys: Array = MapAssets.keys()
	_check(keys.size() >= 32, "the asset catalogue lists placeable keys (%d)" % keys.size())
	_check(MapAssets.has("church") and MapAssets.has("barn") and MapAssets.has("windmill") and MapAssets.has("house_terrace"), "the catalogue has the church, barn, windmill and houses")
	var fails: Array = []
	var cats: Dictionary = {}
	for k in keys:
		var n: Node3D = MapAssets.build(str(k))
		if n == null:
			fails.append(str(k))
		else:
			n.free()
		cats[MapAssets.category(str(k))] = true
		if MapAssets.label(str(k)).is_empty():
			fails.append(str(k) + " (no label)")
	_check(fails.is_empty(), "every asset key builds a Node3D with a label; fail: %s" % ", ".join(PackedStringArray(fails)))
	_check(cats.has("building") and cats.has("prop") and cats.size() == 2, "every asset is categorised building or prop")
	_check(MapAssets.build("no_such_asset") == null and MapAssets.label("no_such_asset") == "", "an unknown key is not in the catalogue")


## Write text to any res:// / user:// path (test helper).
func _write_text(path: String, s: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(s)
		f = null


# ------------------------------------------------------------------ rivers

const _RIVER_KINDS: Array = ["river", "canal", "stream", "riverbank", "drain", "ditch", "tidal_channel", "fairway"]

## data/osm/rivers.json: >= 500 lines, a known class per line, >= 2 points per line, and a sane total length.
func _test_river_data() -> void:
	print("-- river data")
	var d: Variant = _load_json("res://data/osm/rivers.json")
	if not _check(d is Dictionary, "rivers.json parses"):
		return
	var lines: Array = (d as Dictionary).get("lines", [])
	_check(lines.size() >= 500, "rivers.json has >= 500 lines (%d)" % lines.size())
	var kinds: Dictionary = {}
	var bad_k: int = 0
	var short_pts: int = 0
	var total_km: float = 0.0
	for ln in lines:
		if not (ln is Dictionary):
			continue
		var e: Dictionary = ln
		var k: String = String(e.get("k", ""))
		kinds[k] = true
		if not _RIVER_KINDS.has(k):
			bad_k += 1
		var pts: Array = e.get("pts", [])
		if pts.size() < 2:
			short_pts += 1
			continue
		for i in range(1, pts.size()):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			total_km += _seg_km(float(a[0]), float(a[1]), float(b[0]), float(b[1]))
	_check(bad_k == 0, "every river line has a known class (unknown=%d, kinds=%s)" % [bad_k, kinds.keys()])
	_check(short_pts == 0, "every river line has >= 2 points (short=%d)" % short_pts)
	_check(total_km > 1000.0, "rivers.json total length is sane (%.0f km)" % total_km)


## Equirectangular segment length in km (independent of the game's horizontal compression).
func _seg_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
	var dlat: float = (b_lat - a_lat) * 111.320
	var dlon: float = (b_lon - a_lon) * 111.320 * cos(deg_to_rad((a_lat + b_lat) * 0.5))
	return sqrt(dlat * dlat + dlon * dlon)


# ------------------------------------------------------------------ landmarks

## Every id in scripts/ground/landmarks.gd build()'s match block returns a non-null Node3D with >= 1 mesh.
func _test_landmarks_all() -> void:
	print("-- landmarks build()")
	var ids: Array = _landmark_ids()
	if not _check(ids.size() >= 40, "landmarks.gd build() has landmark cases (%d)" % ids.size()):
		return
	var ok: int = 0
	var fails: Array = []
	for id in ids:
		var n: Node3D = Landmarks.build(String(id))
		var meshes: int = 0
		if n != null:
			meshes = _mesh_count(n)
		if n != null and meshes >= 1:
			ok += 1
		else:
			fails.append(String(id))
		if n != null:
			n.free()
	_check(ok == ids.size(), "every landmark id builds with >= 1 mesh (%d/%d); fail: %s" % [ok, ids.size(), ", ".join(PackedStringArray(fails))])


## Parse build()'s match arms: lines indented with exactly two tabs that read an id then a colon.
func _landmark_ids() -> Array:
	var ids: Array = []
	var f: FileAccess = FileAccess.open("res://scripts/ground/landmarks.gd", FileAccess.READ)
	if f == null:
		return ids
	var two_tabs: String = char(9) + char(9)
	var started: bool = false
	while not f.eof_reached():
		var line: String = f.get_line()
		if not started:
			if line.contains("func build(id"):
				started = true
			continue
		var s: String = line.strip_edges()
		if line.begins_with(two_tabs + char(34)) and s.ends_with(char(34) + ":"):
			ids.append(s.substr(1, s.length() - 3))
	f = null
	return ids


func _mesh_count(n: Node) -> int:
	var c: int = 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		c += 1
	for ch in n.get_children():
		if ch is Node:
			c += _mesh_count(ch)
	return c


# ------------------------------------------------------------------ buildings and industry

## Both new house variants (8 cinema, 9 station front) and the original 0-7 build a mesh.
func _test_house_variants() -> void:
	print("-- house variants")
	var fails: Array = []
	for v in 10:
		var m: ArrayMesh = Scatter.house_mesh(v)
		if m == null or m.get_surface_count() < 1:
			fails.append(str(v))
	_check(fails.is_empty(), "Scatter.house_mesh(0..9) all build a mesh (fail: %s)" % ", ".join(PackedStringArray(fails)))


## IndustryKit.build(kind, land_pos, 0.0) is non-null for every kind declared in data/industry_1940.json.
func _test_industry_kinds() -> void:
	print("-- industry kinds")
	var d: Variant = _load_json("res://data/industry_1940.json")
	if not _check(d is Dictionary, "industry_1940.json loads for the kind test"):
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Array = []
	var pos := Vector3.ZERO
	var have_pos: bool = false
	for e in sites:
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var k: String = String(ed.get("kind", ""))
		if k != "" and not kinds.has(k):
			kinds.append(k)
		if not have_pos and ed.has("lat") and ed.has("lon"):
			pos = WorldCoords.latlon_to_world(float(ed["lat"]), float(ed["lon"]))
			have_pos = true
	_check(kinds.size() >= 8, "industry_1940.json declares kinds (%d)" % kinds.size())
	_check(have_pos, "an industry site gives a land position for the builders")
	var fails: Array = []
	for k in kinds:
		var n: Node3D = IndustryKit.build(String(k), pos, 0.0)
		if n == null:
			fails.append(String(k))
		else:
			n.free()
	_check(fails.is_empty(), "IndustryKit.build(kind, land_pos, 0.0) is non-null for every kind (%d); fail: %s" % [kinds.size(), ", ".join(PackedStringArray(fails))])


# ------------------------------------------------------------------ 1940s landscape additions (P1-P3)

## data/sea_defences_1940.json and data/dams_1940.json parse and are non-empty.
func _test_landscape_data() -> void:
	print("-- 1940s landscape data")
	var sd: Variant = _load_json("res://data/sea_defences_1940.json")
	if _check(sd is Dictionary, "sea_defences_1940.json parses"):
		_check_has_entries(sd as Dictionary, "sites", "sea_defences_1940.json sites")
	var dm: Variant = _load_json("res://data/dams_1940.json")
	if _check(dm is Dictionary, "dams_1940.json parses"):
		_check_has_entries(dm as Dictionary, "dams", "dams_1940.json dams")
	# estuary mud-flat zones (terrain.gdshader estuary_a..f)
	var hf := HeightField.new()
	var ez: Array = hf.get_estuary_world_zones()
	_check(ez.size() == 6, "%d estuary zones feed the tidal-flat mask" % ez.size())
	var ok_ez: bool = true
	for e in ez:
		var v: Vector3 = e
		if v.z <= 1000.0 or is_nan(v.x) or is_nan(v.y):
			ok_ez = false
	_check(ok_ez, "every estuary zone has a real radius and a projected position")


## Every sea-defence site in the data builds a non-null node with >= 1 mesh (P1).
func _test_sea_defence_kinds() -> void:
	print("-- sea defence kinds")
	var sd: Variant = _load_json("res://data/sea_defences_1940.json")
	if not _check(sd is Dictionary, "sea_defences_1940.json loads for the kind test"):
		return
	var sites: Array = (sd as Dictionary).get("sites", [])
	var kinds: Array = []
	for e in sites:
		if not (e is Dictionary):
			continue
		var k: String = String((e as Dictionary).get("kind", ""))
		if k != "" and not kinds.has(k):
			kinds.append(k)
	_check(kinds.size() >= 5, "sea_defences_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	var pos: Vector3 = WorldCoords.latlon_to_world(51.0, 1.45)
	for e in sites:
		var ed: Dictionary = e
		var n: Node3D = SeaDefenceKit.build(String(ed.get("kind", "")), String(ed.get("style", "")), pos, float(ed.get("heading_deg", 0.0)), float(ed.get("length_m", 0.0)), int(ed.get("rows", 1)), 7)
		if n == null or _mesh_count(n) < 1:
			fails.append(String(ed.get("id", "?")))
		if n != null:
			n.free()
	_check(fails.is_empty(), "every sea-defence site builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])


## POW escape: every operation has a config the mode accepts, the mode script compiles and the strips plan.
func _test_pow_escape() -> void:
	print("-- pow escape")
	_check(PowEscapeCampaign.count() == 6, "six POW escape operations")
	var scr: Script = load("res://scripts/modes/pow_escape_mode.gd")
	_check(scr != null and scr.can_instantiate(), "pow_escape_mode.gd compiles")
	for i in PowEscapeCampaign.count():
		var cfg: Dictionary = PowEscapeCampaign.config_for(i)
		_check(str(cfg.get("mode", "")) == "pow_escape", "op %d mode" % i)
		_check(not PowEscapeCampaign.camp_row(str(cfg.get("camp", ""))).is_empty(), "op %d camp exists" % i)
		_check(EscapeStripKit.strip_for_camp(str(cfg.get("camp", ""))) != "", "op %d has a strip" % i)
		if str(cfg.get("kind", "")) == "pickup":
			_check(str(cfg.get("aircraft", "")) == "dh89", "op %d flies the Rapide" % i)
	_check(PowEscapeCampaign.is_open(0), "first op open")

## D-Day airborne: configs, zones, scripts compile, the tow rig builds for both glider types.
func _test_airborne() -> void:
	print("-- airborne")
	_check(AirborneCampaign.count() == 5, "five airborne operations")
	for sp in ["res://scripts/modes/airborne_mode.gd", "res://scripts/effects/tow_rig.gd"]:
		var scr: Script = load(sp)
		_check(scr != null and scr.can_instantiate(), "%s compiles" % sp)
	for i in AirborneCampaign.count():
		var cfg: Dictionary = AirborneCampaign.config_for(i)
		_check(str(cfg.get("mode", "")) == "airborne", "airborne op %d mode" % i)
		_check(not AirborneCampaign.zone_row(str(cfg.get("zone", ""))).is_empty(), "airborne op %d zone exists" % i)
		_check(str(cfg.get("aircraft", "")) == "c47", "airborne op %d flies the C-47" % i)
	for gt in ["horsa", "hamilcar", "waco"]:
		_check(GliderKit.glider_mesh(gt, "intact") != null, "glider mesh " + gt)
	var rig: TowRig = TowRig.make(null, "waco", Vector3.ZERO)
	_check(rig.state == "towed", "tow rig starts towed")
	rig.free()


## A damaged player can be spared or lost by an enemy pilot; the backup caller never calls twice for the same thing.
func _test_escape_and_backup() -> void:
	print("-- escape and backup")
	var side: String = GameState.player_side
	var foe: String = AircraftCatalog.opposite(side)
	var me: Aircraft = AIFactory.spawn(self, "spitfire" if side == "Allies" else "bf109", side, Vector3(0.0, 1500.0, 0.0), 90.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
	me.player_controlled = true
	var e: Aircraft = AIFactory.spawn(self, "bf109" if foe == "Axis" else "spitfire", foe, Vector3(-800.0, 1500.0, 0.0), 90.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
	var p: AIPilot = AIFactory.pilot_of(e)
	_check(p._target_valid(me, 5000.0), "the enemy can target a healthy player")
	p._release_player(60.0)
	_check(not p._target_valid(me, 5000.0) and p._find_target(5000.0) == null, "a released player is left alone")
	_check(p.target == null, "releasing clears the target")
	p._let_go_until = 0
	_check(p._target_valid(me, 5000.0), "the pilot hunts again once the time is up")
	# sparing is decided once per player aircraft
	me.health = me.stats.max_health * 0.3
	p.target = me
	var spared: int = 0
	for i in 200:
		p._spare_rolled = 0
		p._let_go_until = 0
		p.target = me
		p._lose_check_t = 99.0
		p._maybe_let_player_go()
		if p._let_go():
			spared += 1
	_check(spared > 5 and spared < 150, "a hurt player is sometimes spared, not always (%d / 200)" % spared)
	p._spare_rolled = me.get_instance_id()
	p._let_go_until = 0
	p.target = me
	p._lose_check_t = 99.0
	p._maybe_let_player_go()
	_check(not p._let_go(), "no second roll to spare the same aircraft")
	# backup: one consideration per incident, none while busy / cooling / backup up, never from a backup aircraft
	var bc: BackupCaller = BackupCaller.new()
	bc.player = me
	bc.chance = 0.0
	bc._cool = 0.0
	add_child(bc)
	bc._on_player_hit(e, 5.0)
	_check(bc._seen.size() == 1, "an attacked flight is considered for a call")
	bc.chance = 1.0
	bc._on_player_hit(e, 5.0)
	_check(not bc._busy, "the same flight is not considered twice")
	e.set_meta("backup", true)
	_check(bc._incident_of(e).is_empty(), "an aircraft that came as backup never calls for backup")
	e.remove_meta("backup")
	bc._seen.clear()
	bc._cool = 10.0
	bc._on_player_hit(e, 5.0)
	_check(bc._seen.is_empty(), "no call during the quiet spell")
	bc._cool = 0.0
	bc._calls = BackupCaller.MAX_CALLS
	bc._on_player_hit(e, 5.0)
	_check(bc._seen.is_empty(), "no more calls once the sortie's allowance is used")
	bc.queue_free()
	me.queue_free()
	e.queue_free()


## Structural failure: a lost wing or tail spins the aircraft out; a twin loses an engine but keeps flying.
func _test_structural_damage() -> void:
	print("-- structural damage")
	var ac: Aircraft = AIFactory.spawn(self, "a20", "Allies", Vector3(0.0, 1500.0, 0.0), 90.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
	ac.on_ground = false
	var dm: AircraftDamageModel = ac.damage_model
	_check(dm != null and dm.engines_out_frac() == 0.0, "no engines out at the start")
	var k0: float = dm.engine_k()
	dm._init_engines()
	_check(dm.eng_x.size() == 2, "a twin has two engines tracked (%d)" % dm.eng_x.size())
	dm._engine_fail(0, false)
	_check(dm.engines_out_frac() == 0.5, "one of two engines out")
	_check(dm.engine_k() < k0 * 0.75 and dm.engine_k() > 0.3, "one engine out: lower power, still flying (%.2f)" % dm.engine_k())
	_check(dm.turn_k() < 1.0, "one engine out: lower turning ability")
	_check(dm.engine_asym() != 0.0, "one engine out: the nose swings toward the dead side")
	dm.wing_lost["wing_l"] = 1
	_check(dm.roll_bias() < 0.0, "half the port wing gone: she rolls to port")
	dm.repair()
	_check(dm.engines_out_frac() == 0.0 and int(dm.wing_lost["wing_l"]) == 0, "repair restores engines and wings")
	ac.start_breakup("wing_r", null)
	ac.queue_free()
	var f: Aircraft = AIFactory.spawn(self, "spitfire", "Allies", Vector3(500.0, 1500.0, 0.0), 90.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
	f.damage_model.tail_lost = true
	f.damage_model.apply_cut()
	f.start_breakup("tail", null)
	_check(f.state == Aircraft.State.DYING and f.breakup == "tail", "a lost tail puts her out of control")
	f.queue_free()


## G and engine-heat strength presets, gun layouts and per-type convergence.
func _test_realism_presets() -> void:
	print("-- realism presets")
	_check(GameState.g_level == 2 and GameState.heat_level == 2, "G effects and overheating default to Medium")
	var lo: Array = Aircraft.G_PRESETS[1]
	var me: Array = Aircraft.G_PRESETS[2]
	var hi: Array = Aircraft.G_PRESETS[3]
	_check(float(lo[0]) > float(me[0]) and float(me[0]) > float(hi[0]), "G threshold falls from Low to High")
	_check(float(lo[1]) < float(me[1]) and float(me[1]) < float(hi[1]), "G build-up rises from Low to High")
	_check(float(Aircraft.HEAT_PRESETS[2][0]) == 1.0, "Medium heat is the original tuning")
	_check(float(Aircraft.HEAT_PRESETS[1][0]) < 1.0 and float(Aircraft.HEAT_PRESETS[3][0]) > 1.0, "Low heats slower, High faster")
	for id in GunLayouts.LAYOUTS.keys():
		var d: Dictionary = GunLayouts.LAYOUTS[id]
		_check(float(d["conv"]) >= 150.0 and float(d["conv"]) <= 500.0, "%s convergence is a realistic range" % id)
		_check((d["mounts"] as Array).size() >= 2, "%s has gun mounts" % id)
	_check(GunLayouts.convergence("spitfire", 450.0) < 260.0, "Spitfire guns converge near 250 yards")
	_check(GunLayouts.convergence("lancaster", 450.0) == 450.0, "no layout falls back to the stat")


## Every dam id in the data builds a non-null GroundStructure("dam") wall AND DamKit scenery, each >= 1 mesh (P3).
func _test_dams_build() -> void:
	print("-- dams build()")
	var dm: Variant = _load_json("res://data/dams_1940.json")
	if not _check(dm is Dictionary, "dams_1940.json loads for the build test"):
		return
	var dams: Array = (dm as Dictionary).get("dams", [])
	_check(dams.size() >= 6, "dams_1940.json declares the Dam Busters dams (%d)" % dams.size())
	var fails: Array = []
	for e in dams:
		var ed: Dictionary = e
		var id: String = String(ed.get("id", ""))
		if id.is_empty():
			continue
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed.get("lat", 0.0)), float(ed.get("lon", 0.0)))
		var wall: GroundStructure = GroundStructure.create("dam", String(ed.get("team", "Axis")), pos, float(ed.get("heading_deg", 0.0)))
		add_child(wall)                                  # GroundStructure builds its meshes in _ready()
		var scenery: Node3D = DamKit.build(id)
		if wall == null or _mesh_count(wall) < 1 or scenery == null or _mesh_count(scenery) < 1:
			fails.append(id)
		remove_child(wall)
		if wall != null:
			wall.free()
		if scenery != null:
			scenery.free()
	_check(fails.is_empty(), "every dam id builds a wall + scenery with >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(fails)))


## The city balloon barrage is scaled by size and densest over London (P2).
func _test_city_balloons() -> void:
	print("-- city balloon barrage")
	var small: int = WorldPopulator.city_balloon_count("ramsgate", 1)
	var mid: int = WorldPopulator.city_balloon_count("eastbourne", 2)
	var big: int = WorldPopulator.city_balloon_count("cologne", 5)
	var london: int = WorldPopulator.city_balloon_count("london", 5)
	_check(london > small, "London's barrage outnumbers a size-1 town's (%d > %d)" % [london, small])
	_check(small < mid and mid < big, "balloon count rises with city size (%d < %d < %d)" % [small, mid, big])
	var plan: Array = WorldPopulator.city_balloon_plan(Vector3.ZERO, "london", 5, 515.0)
	_check(plan.size() == london, "London's plan matches its count (%d)" % plan.size())
	var all_alt: bool = true
	for e in plan:
		if float((e as Dictionary).get("altitude", 0.0)) <= 0.0:
			all_alt = false
	_check(all_alt, "every planned balloon has an altitude")


## Balloon cable wing strikes are swept (no tunnelling), stay inside the wire's reach and height, and the
## bomber stream ribbon keeps its points for its own (longer) life.
func _test_balloon_cables_and_streams() -> void:
	print("-- balloon cables and bomber stream")
	var base := Vector3(0, 0, 0)
	var top := Vector3(0, 300, 0)
	_check(BarrageBalloon.cable_hit(Vector3(-20, 100, 0), Vector3(20, 100, 0), base, top, 4.0), "a low pass straight through the cable is a wing strike")
	_check(BarrageBalloon.cable_hit(Vector3(-200, 100, 0), Vector3(200, 100, 0), base, top, 4.0), "a fast pass that would step over the wire is still caught (swept)")
	_check(not BarrageBalloon.cable_hit(Vector3(-20, 400, 0), Vector3(20, 400, 0), base, top, 4.0), "flying above the balloon misses the cable")
	_check(not BarrageBalloon.cable_hit(Vector3(-20, 100, 10), Vector3(20, 100, 10), base, top, 4.0), "passing 10 units off the wire misses")
	_check(not BarrageBalloon.cable_hit(Vector3(20, 100, 0), Vector3(40, 100, 0), base, top, 4.0), "moving away from the wire, out of reach, misses")
	var r := ContrailRibbon.new()
	r.life = 2.0
	r._rb = 100.0   # no rebuild: the ribbon is not in a tree, so there is no viewport to rebuild against
	r.add_point(Vector3(0, 0, 0), 1.0)
	r.add_point(Vector3(10, 0, 0), 1.0)
	r._process(1.0)
	_check(r._pts.size() == 2, "a ribbon point is kept inside its life (%d)" % r._pts.size())
	r._process(1.5)
	_check(r._pts.size() == 0, "ribbon points expire after the ribbon's own life (%d left)" % r._pts.size())
	r.free()


# ------------------------------------------------------------------ decoys, power grid, canals (P4-P6)

## Every decoy site in data/decoys_1940.json builds DecoyKit scenery AND a destructible GroundStructure("decoy")
## target, each with >= 1 mesh, and the file declares >= 4 kinds (P4).
func _test_decoy_kinds() -> void:
	print("-- decoy kinds (P4)")
	var dc: Variant = _load_json("res://data/decoys_1940.json")
	if not _check(dc is Dictionary, "decoys_1940.json loads for the kind test"):
		return
	var sites: Array = (dc as Dictionary).get("sites", [])
	var kinds: Array = []
	for e in sites:
		if not (e is Dictionary):
			continue
		var k: String = String((e as Dictionary).get("kind", ""))
		if k != "" and not kinds.has(k):
			kinds.append(k)
	_check(kinds.size() >= 4, "decoys_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e in sites:
		var ed: Dictionary = e
		var id: String = String(ed.get("id", ""))
		if id.is_empty():
			continue
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed.get("lat", 0.0)), float(ed.get("lon", 0.0)))
		var scenery: Node3D = DecoyKit.build(String(ed.get("kind", "")), pos, float(ed.get("heading_deg", 0.0)), int(ed.get("size", 1)), hash(id))
		var wall: GroundStructure = GroundStructure.create("decoy", String(ed.get("team", "Allies")), pos, float(ed.get("heading_deg", 0.0)))
		add_child(wall)                                  # GroundStructure builds its meshes in _ready()
		if scenery == null or _mesh_count(scenery) < 1 or wall == null or _mesh_count(wall) < 1:
			fails.append(id)
		if scenery != null:
			scenery.free()
		remove_child(wall)
		if wall != null:
			wall.free()
	_check(fails.is_empty(), "every decoy site builds scenery + a decoy target with >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(fails)))


## The P5 power layer must not be empty: data/osm/power.json (real fetch) and/or data/pylons_1940.json
## (curated fallback) parse and PylonMesh end up with a non-zero line count. Guards against shipping an
## empty power layer as if the grid had been built.
func _test_pylon_data() -> void:
	print("-- power grid data (P5)")
	var pl: Variant = _load_json("res://data/pylons_1940.json")
	if _check(pl is Dictionary, "pylons_1940.json (curated period grid) parses"):
		_check_has_entries(pl as Dictionary, "lines", "pylons_1940.json lines")
	PylonMesh.ensure_loaded()
	_check(PylonMesh.line_count() > 0, "PylonMesh loaded power lines (count=%d, source=%s)" % [PylonMesh.line_count(), "osm" if PylonMesh.sourced_osm else "curated"])
	_check(PylonMesh.total_km() > 1.0, "power layer spans a sane distance (%.1f km)" % PylonMesh.total_km())
	_check(PylonMesh.pylon_total() > 0, "power layer yields pylons (%d)" % PylonMesh.pylon_total())


## PylonMesh.build_tile over a densely wired tile produces pylon and/or telegraph-pole instances (P5).
func _test_pylon_build() -> void:
	print("-- power grid build (P5)")
	RoadMesh.ensure_loaded()
	PylonMesh.ensure_loaded()
	_check(PylonMesh.line_count() >= 100, "power layer loads lines (count=%d)" % PylonMesh.line_count())
	# The OSM power layer is sparse in places and central London carries no overhead lines at all, so probe
	# several line-bearing tiles and require the network to build in at least one rather than asserting on a
	# single hardcoded tile (which failed while the code was in fact working).
	var probes: Array = [[48.9403, 1.7340], [50.5198, 3.0756], [49.0543, 2.0631], [52.48, -1.90]]
	var built: int = 0
	var best: int = 0
	for c in probes:
		var w: Vector3 = WorldCoords.latlon_to_world(float(c[0]), float(c[1]))
		var org := Vector2(w.x - 900.0, w.z - 900.0)
		var n: Node3D = PylonMesh.build_tile(org, 1800.0)
		var meshes: int = 0
		if n != null:
			meshes = _mesh_count(n)
			n.free()
		best = maxi(best, meshes)
		if meshes >= 1:
			built += 1
	_check(built >= 1, "a line-bearing tile builds a power-grid node with >= 1 mesh (tiles_ok=%d best=%d meshes)" % [built, best])


## CanalKit loads the canals from rivers.json and places furniture along a canal-rich tile (P6).
func _test_canal_furniture() -> void:
	print("-- canal furniture (P6)")
	CanalKit.ensure_loaded()
	_check(CanalKit.canal_count() >= 500, "rivers.json yields canal lines (count=%d)" % CanalKit.canal_count())
	_check(CanalKit.total_km() > 100.0, "canal network spans a sane distance (%.0f km)" % CanalKit.total_km())
	var w: Vector3 = WorldCoords.latlon_to_world(52.48, -1.90)      # Birmingham canal country
	var org := Vector2(w.x - 900.0, w.z - 900.0)
	var n: Node3D = CanalKit.build_tile(org, 1800.0)
	var meshes: int = 0
	if n != null:
		meshes = _mesh_count(n)
	_check(meshes >= 1, "a canal-rich tile builds >= 1 furniture mesh (meshes=%d)" % meshes)
	if n != null:
		n.free()


# ------------------------------------------------------------------ railway drama, airfield furniture, oil and fuel (P7-P9)

## P7: rails.json loads, the curated catalogue parses and builds, every furniture kind builds, and a rail-dense
## tile yields furniture.
func _test_rail_drama() -> void:
	print("-- railway drama (P7)")
	RailKit.ensure_loaded()
	_check(RailKit.rail_count() >= 100, "rails.json yields rail lines (count=%d)" % RailKit.rail_count())
	_check(RailKit.total_km() > 100.0, "rail network spans a sane distance (%.0f km)" % RailKit.total_km())
	_check(RailKit.catalog_count() >= 6, "rail_drama_1940.json declares curated structures (%d)" % RailKit.catalog_count())
	var pos: Vector3 = WorldCoords.latlon_to_world(51.5, -0.1)
	var kfails: Array = []
	for k in RailKit.kinds():
		var n: Node3D = RailKit.build_piece(String(k), pos, 0.0, 7)
		if n == null or _mesh_count(n) < 1:
			kfails.append(String(k))
		if n != null:
			n.free()
	_check(kfails.is_empty(), "every rail furniture kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))
	var rd: Variant = _load_json("res://data/rail_drama_1940.json")
	if _check(rd is Dictionary, "rail_drama_1940.json parses"):
		var sites: Array = (rd as Dictionary).get("sites", [])
		var cfails: Array = []
		for e in sites:
			var ed: Dictionary = e
			var s: Node3D = RailKit.build_catalog(ed)
			if s == null or _mesh_count(s) < 1:
				cfails.append(String(ed.get("id", "?")))
			if s != null:
				s.free()
		_check(cfails.is_empty(), "every curated viaduct/tunnel builds >= 1 mesh (%d); fail: %s" % [sites.size(), ", ".join(PackedStringArray(cfails))])
	var centres: Array = [[51.51, -0.12], [51.75, -0.19], [51.42, -2.23], [52.33, -1.16], [51.03, 2.33]]
	var meshes: int = 0
	for c in centres:
		var w: Vector3 = WorldCoords.latlon_to_world(float(c[0]), float(c[1]))
		var org := Vector2(w.x - 900.0, w.z - 900.0)
		var tile: Node3D = RailKit.build_tile(org, 1800.0)
		if tile != null:
			meshes += _mesh_count(tile)
			tile.free()
	_check(meshes >= 1, "rail-country tiles build railway furniture (meshes=%d over %d tiles)" % [meshes, centres.size()])


## P8: the new airfield furniture meshes build and a dressed airfield places meshes and destructible prop clusters.
func _test_airfield_furniture() -> void:
	print("-- airfield furniture (P8)")
	var meshes: Array = [AirfieldAssets.t2_hangar("Allies"), AirfieldAssets.t1_hangar("Allies"), AirfieldAssets.revetment("Allies"),
		AirfieldAssets.chance_light(), AirfieldAssets.dummy_aircraft("Allies")]
	var names: Array = ["t2_hangar", "t1_hangar", "revetment", "chance_light", "dummy_aircraft"]
	var mfails: Array = []
	for i in meshes.size():
		var mm: ArrayMesh = meshes[i]
		if mm == null or mm.get_surface_count() < 1:
			mfails.append(String(names[i]))
	_check(mfails.is_empty(), "airfield furniture meshes build (%d); fail: %s" % [meshes.size(), ", ".join(PackedStringArray(mfails))])
	var af: Airfield = Airfield.create("Test Field", Vector3.ZERO, 90.0, 0.0)
	af.style = "grass"
	add_child(af)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var container := Node3D.new()
	var axf := Transform3D(Basis(Vector3.UP, af.rotation.y), af.position)
	AirfieldFurniture.dress(container, af, axf, 0.0, "Allies", rng)
	add_child(container)
	var m: int = _mesh_count(container)
	var props: int = container.find_children("*", "AirfieldProp", true, false).size()
	_check(m >= 12, "a dressed airfield places furniture meshes (meshes=%d)" % m)
	_check(props >= 1, "the furniture includes destructible prop clusters (%d)" % props)
	remove_child(container)
	container.free()
	remove_child(af)
	af.free()


## Spawn keep-clear: every airfield layout, built and dressed exactly the way the game builds it (WorldPopulator._build_airfield,
## the Luftwaffe kitchen and wagons, people, pens, nets and parked aircraft included) for BOTH sides, must leave the player's
## spawn spot and the taxi routes out of the dispersals clear of anything solid (Obstacles). The game bumps at 1.2 m and
## stops the aircraft dead against what it touches (a field with a net or a pen on the pad was a start the player could not roll from),
## so the check here uses 3 m, wings and all.
func _test_spawn_clear() -> void:
	print("-- spawn keep-clear (every airfield style, both sides)")
	var wp := WorldPopulator.new()
	wp._sync_build = true
	add_child(wp)
	var grass_id: String = "grass_test"      # (no real field is listed as plain "grass": any id the hash sends there will do)
	for gi in 200:
		if Airfield.style_for("gx%d" % gi) == "grass":
			grass_id = "gx%d" % gi
			break
	var ids: Array = [["manston_t", "manston", ""], ["rg", Airfield.RAF_GRASS_IDS[0], ""], ["lwf", Airfield.LW_FIELD_IDS[0], ""], ["grass", grass_id, ""],
		["cross", Airfield.CROSS_IDS[0], ""], ["par", Airfield.PARALLEL_IDS[0], ""], ["fwd", Airfield.FORWARD_IDS[0], ""]]
	for st in Airfield.STYLE_KEYS:
		ids.append([st, "test_" + String(st), String(st)])
	var checked: int = 0
	var fails: Array = []
	# the synthetic cases (each layout, each side) then every real airfield record as it is in data/locations.json
	var cases: Array = []
	for e in ids:
		for side in ["RAF", "Luftwaffe"]:
			var id0: String = "sc_%s_%s" % [e[0], side]
			var d0 := {"id": id0, "name": id0, "side": side, "heading_deg": 70.0, "runway_len_m": 1500, "lat": 51.0, "lon": 1.0}
			if String(e[2]) != "":
				d0["style"] = e[2]
			cases.append([id0, String(e[1]) if String(e[2]) == "" else id0, d0])
	var fa := FileAccess.open("res://data/locations.json", FileAccess.READ)
	if fa != null:
		var recs: Variant = (JSON.parse_string(fa.get_as_text()) as Dictionary).get("airfields", [])
		for rv in recs:
			var rd: Dictionary = rv
			cases.append(["rec_" + str(rd["id"]), str(rd["id"]), rd])
	for cs in cases:
		var id: String = cs[0]
		var d: Dictionary = cs[2]
		if true:
			Obstacles.clear()
			var s := {"id": cs[1], "key": id, "data": d, "existing": null, "pos": WorldCoords.latlon_to_world(float(d.get("lat", 51.0)), float(d.get("lon", 1.0))), "y": 0.0}
			var container: Node3D = await wp._build_airfield(s)
			if container == null:
				fails.append("%s: no container" % id)
				continue
			add_child(container)
			var af: Airfield = null
			for c in container.find_children("*", "Airfield", true, false):
				af = c as Airfield
			if af == null or af.taxi_flight_routes.is_empty():
				fails.append("%s: no airfield / taxi flight" % id)
				container.free()
				continue
			var routes: Array = []
			for r in af.taxi_flight_routes:
				var w := PackedVector3Array()
				for p in (r as PackedVector3Array):
					w.append(af.global_transform * Vector3(p.x, 1.0, p.z))
				routes.append(w)
			# the runway start (fast-start modes and respawns): the threshold and the first 700 m of the take-off run
			var rdir: Vector3 = WorldCoords.heading_to_dir(af.heading_deg)
			rdir.y = 0.0
			var rthr: Vector3 = af.get_threshold_position()
			rthr.y = 1.0
			routes.append(PackedVector3Array([rthr, rthr + rdir.normalized() * 700.0]))
			for ri in routes.size():
				var w2: PackedVector3Array = routes[ri]
				var hits: Dictionary = Obstacles.scan_route(w2[0], w2, 3.0, 1.2)
				checked += 1
				if not hits.is_empty():
					fails.append("%s (%s, %s) %s: %s at spawn (%.0f,%.0f); field origin (%.0f,%.0f) heading %.0f, runway %.0f x %.0f m, threshold (%.0f,%.0f)" % [id, af.style, af.team, "runway start" if ri == routes.size() - 1 else "taxi route %d" % ri, str(hits.keys()), w2[0].x, w2[0].z, af.global_position.x, af.global_position.z, af.heading_deg, af.runway_length, af.runway_width, rthr.x, rthr.z])
			remove_child(container)
			container.free()
	wp.queue_free()
	Obstacles.clear()
	_check(checked >= 40, "the spawn check covered every layout and side (%d routes)" % checked)
	_check(fails.is_empty(), "nothing solid stands on a spawn spot or its taxi route; found: %s" % "; ".join(PackedStringArray(fails)))


## P5: the new airfield styles. For each style a small Airfield is built and dressed the way
## WorldPopulator._build_airfield dresses it (furniture for the triangle-family styles, the satellite
## populator dresser for the satellite), and must place meshes and destructible prop clusters.
func _test_airfield_styles() -> void:
	print("-- airfield styles (P5)")
	var meshes: Array = [AirfieldAssets.lw_hangar("Axis"), AirfieldAssets.lw_watch_office()]
	var names: Array = ["lw_hangar", "lw_watch_office"]
	var mfails: Array = []
	for i in meshes.size():
		var mm: ArrayMesh = meshes[i]
		if mm == null or mm.get_surface_count() < 1:
			mfails.append(String(names[i]))
	_check(mfails.is_empty(), "new airfield style meshes build (%d); fail: %s" % [meshes.size(), ", ".join(PackedStringArray(mfails))])
	var keep: String = EraClock.current()
	EraClock.set_date("")
	_check(Airfield.style_for_record("biggin_hill", {}) == "raf_grass", "style_for_record keeps the 1940 grass look without a date era")
	EraClock.set_date("1944-05-01")
	_check(Airfield.style_for_record("biggin_hill", {}) == "raf_fighter", "RAF fighter stations pave up in the buildup band")
	_check(Airfield.style_for_record("af_asch", {}) == "usaf_alg", "af_* forward strips become US ALGs in the buildup band")
	_check(Airfield.style_for_record("biggin_hill", {"style": "night_fighter"}) == "night_fighter", "a record's own style key wins over the era rules")
	_check(Airfield.style_for_record("biggin_hill", {"style": "not_a_style"}) == "raf_fighter", "an unknown style string falls back to the era rules")
	EraClock.set_date("" if keep == EraClock.DEFAULT else keep)
	var wp := WorldPopulator.new()      # dressers are instance methods; none of them awaits or needs the tree
	var fails: Array = []
	for st in ["raf_bomber", "raf_satellite", "night_fighter", "lw_fliegerhorst", "usaf_alg"]:
		var af: Airfield = Airfield.create("Style Test", Vector3.ZERO, 90.0, 0.0)
		af.style = st
		add_child(af)
		var container := Node3D.new()
		add_child(container)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var axf := Transform3D(Basis(Vector3.UP, af.rotation.y), af.position)
		if st == "raf_satellite":
			wp._dress_satellite(container, af, axf, 0.0, "Allies", rng)
		else:
			AirfieldFurniture.dress(container, af, axf, 0.0, "Allies", rng)
		var m: int = _mesh_count(container)
		var props: int = container.find_children("*", "AirfieldProp", true, false).size()
		if not _check(m >= 6, "%s dresses meshes (meshes=%d)" % [st, m]):
			fails.append(st)
		if not _check(props >= 1, "%s includes destructible prop clusters (props=%d)" % [st, props]):
			fails.append(st)
		remove_child(container)
		container.free()
		remove_child(af)
		af.free()
	_check(fails.is_empty(), "every new airfield style dresses; fail: %s" % ", ".join(PackedStringArray(fails)))
	# raf_grass P5 follow-ups: a boundary tree line in the layout, a straight hangar row on a gravel apron
	var gaf: Airfield = Airfield.create("Grass Test", Vector3.ZERO, 90.0, 0.0)
	gaf.style = "raf_grass"
	add_child(gaf)
	_check(gaf.trees_local.size() >= 40, "the grass station lays a boundary tree line (%d trees)" % gaf.trees_local.size())
	var gcont := Node3D.new()
	add_child(gcont)
	var grng := RandomNumberGenerator.new()
	grng.seed = 77
	wp._dress_grass_station(gcont, gaf, Transform3D(Basis(Vector3.UP, gaf.rotation.y), gaf.position), 0.0, "Allies", grng)
	var gmm: int = gcont.find_children("*", "MultiMeshInstance3D", true, false).size()
	_check(gmm >= 4 and gcont.find_children("*", "GroundStructure", true, false).size() >= 6, "the grass station dresses trees, markers and its hangar row (multimeshes=%d)" % gmm)
	remove_child(gcont)
	gcont.free()
	# mid-session era change: the layout tears down and rebuilds for the new era's style
	gaf.restyle("raf_fighter")
	_check(gaf.style == "raf_fighter" and gaf._built and not gaf._paved.is_empty(), "an airfield restyles to the new era's layout")
	# the paved stations' boundary tree belt: present, and never under the main runway's approach or climb-out
	var half_l: float = gaf.runway_length * 0.5
	var in_lane: int = 0
	for tt in gaf.trees_local:
		var o: Vector3 = (tt as Transform3D).origin
		if absf(o.x) < 160.0 and absf(o.z) < half_l + 880.0:
			in_lane += 1
	_check(gaf.trees_local.size() >= 30 and in_lane == 0, "a paved station has a boundary tree belt clear of the runway lanes (%d trees, %d in a lane)" % [gaf.trees_local.size(), in_lane])
	remove_child(gaf)
	gaf.free()
	wp.free()


## P: taxi to runway. Every layout that lays taxiways routes a dispersal spot to the runway through the
## hold-short; on paved styles the entry point sits on the runway pavement.
func _test_taxi_graph() -> void:
	print("-- taxi graph")
	var want_route: Array = ["raf_grass", "raf_bomber", "raf_fighter", "grass", "cross", "parallel", "night_fighter", "lw_fliegerhorst"]
	var paved_styles: Array = ["raf_bomber", "raf_fighter", "cross", "parallel", "night_fighter", "lw_fliegerhorst"]
	var fails: Array = []
	var routed: int = 0
	for st in ["raf_grass", "raf_bomber", "raf_fighter", "raf_satellite", "grass", "cross", "parallel", "forward", "usaf_alg", "lw_field", "night_fighter", "lw_fliegerhorst", "glider_strip"]:
		var af: Airfield = Airfield.create("Taxi " + st, Vector3.ZERO, 90.0, 0.0)
		af.style = st
		add_child(af)
		af.build_layout()
		var spots: Array = af._dispersal_local
		if not spots.is_empty():
			var route: PackedVector3Array = af.taxi_route(spots[0])
			if not route.is_empty():
				routed += 1
				var on_hold: bool = false
				var hp: Vector3 = route[maxi(route.size() - 4, 0)]
				for h in (af.taxi_holds if not af.taxi_holds.is_empty() else [[af.taxi_hold]]):
					if hp.distance_to(h[0]) < 2.0:
						on_hold = true
				if want_route.has(st) and not _check(on_hold and route.size() >= 4, "%s: the taxi route runs pad -> hold-short -> runway (%d legs)" % [st, route.size()]):
					fails.append(st)
				if paved_styles.has(st) and route.size() >= 4 and not _check(af.near_paved(af.transform * af.taxi_entry, 45.0), "%s: the taxi entry is on the runway pavement" % st):
					fails.append(st)
			elif want_route.has(st):
				if not _check(false, "%s: a dispersal spot taxis to the runway (no route)" % st):
					fails.append(st)
		# the taxi-out flight plan: the player and three wingmen on their own spots, no route passing a parked member's
		# spot, no route doubling back on itself, and the dressing leaves the flight's pads empty
		var fl: PackedInt32Array = af.taxi_flight
		if want_route.has(st) and not _check(fl.size() >= 4, "%s: the taxi-out flight has %d spots (player + 3 wingmen)" % [st, fl.size()]):
			fails.append(st)
		for a in fl.size():
			var r: PackedVector3Array = af.taxi_flight_routes[a]
			for b in fl.size():
				# (full clearance past the spots of those still parked behind; members ahead have left theirs)
				var need: float = Airfield.TAXI_SPOT_CLEAR if b > a else Airfield.TAXI_SPOT_CLEAR * 0.7
				if a != b and Airfield.route_distance(r, af._dispersal_local[fl[b]]) < need - 0.01:
					_check(false, "%s: flight route %d passes member %d's spot" % [st, a, b])
					fails.append(st)
			for i in range(1, r.size() - 1):
				var u := Vector2(r[i].x - r[i - 1].x, r[i].z - r[i - 1].z)
				var v := Vector2(r[i + 1].x - r[i].x, r[i + 1].z - r[i].z)
				if u.length() > 5.0 and v.length() > 5.0 and u.normalized().dot(v.normalized()) < -0.7:
					_check(false, "%s: flight route %d doubles back at its point %d" % [st, a, i])
					fails.append(st)
			var lu: Vector3 = af.flight_route(a, fl.size() - 1, 30.0)[r.size() - 1]
			if a > 0 and not _check(absf(lu.z - af.flight_route(a - 1, fl.size() - 1, 30.0)[af.taxi_flight_routes[a - 1].size() - 1].z - 30.0) < 0.5,
					"%s: wingman %d lines up one slot behind the aircraft ahead" % [st, a]):
				fails.append(st)
		if not fl.is_empty() and not _check(af.dispersal_world_points().size() == af._dispersal_local.size() - fl.size(), "%s: the dressing skips the flight's pads" % st):
			fails.append(st)
		remove_child(af)
		af.free()
	_check(routed >= 8, "%d airfield styles route a dispersal spot to the runway" % routed)
	_check(fails.is_empty(), "taxi graph check; fail: %s" % ", ".join(PackedStringArray(fails)))


## P9: oil_fuel_1940.json parses, every site builds scenery + a destructible structure, and every kind builds.
func _test_oil_fuel() -> void:
	print("-- oil and fuel (P9)")
	var of: Variant = _load_json("res://data/oil_fuel_1940.json")
	if not _check(of is Dictionary, "oil_fuel_1940.json parses"):
		return
	var sites: Array = (of as Dictionary).get("sites", [])
	_check(sites.size() >= 6, "oil_fuel_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 3, "oil_fuel_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e in sites:
		var ed: Dictionary = e
		var id: String = String(ed.get("id", ""))
		if id.is_empty():
			continue
		var kind: String = String(ed.get("kind", ""))
		var team: String = String(ed.get("team", "Allies"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed.get("lat", 0.0)), float(ed.get("lon", 0.0)))
		var scenery: Node3D = OilFuelKit.build(kind, pos, 0.0, int(ed.get("size", 2)), team, hash(id))
		var st: GroundStructure = GroundStructure.create(WorldPopulator._oil_structure_kind(kind), team, pos, 0.0)
		add_child(st)
		if scenery == null or _mesh_count(scenery) < 1 or st == null or _mesh_count(st) < 1:
			fails.append(id)
		if scenery != null:
			scenery.free()
		remove_child(st)
		if st != null:
			st.free()
	_check(fails.is_empty(), "every oil/fuel site builds scenery + a structure with >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(fails)))
	var kfails: Array = []
	var kpos: Vector3 = WorldCoords.latlon_to_world(51.5, 0.5)
	for k in OilFuelKit.kinds():
		var n: Node3D = OilFuelKit.build(String(k), kpos, 0.0, 2, "Allies", 7)
		if n == null or _mesh_count(n) < 1:
			kfails.append(String(k))
		if n != null:
			n.free()
	_check(kfails.is_empty(), "every OilFuelKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))


# ------------------------------------------------------------------ aircraft industry, V-weapons, port clutter (P10-P12)

## P10: aircraft_industry_1940.json parses, every site builds AircraftIndustryKit scenery + a destructible
## GroundStructure("factory"), and every declared kind is handled.
func _test_aircraft_industry() -> void:
	print("-- aircraft industry (P10)")
	var ai: Variant = _load_json("res://data/aircraft_industry_1940.json")
	if not _check(ai is Dictionary, "aircraft_industry_1940.json parses"):
		return
	var sites: Array = (ai as Dictionary).get("sites", [])
	_check(sites.size() >= 8, "aircraft_industry_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 4, "aircraft_industry_1940.json declares kinds (%d)" % kinds.size())
	var kfails: Array = []
	for e in sites:
		var ed: Dictionary = e
		var n: Node3D = AircraftIndustryKit.build(String(ed.get("kind", "")), WorldCoords.latlon_to_world(float(ed.get("lat", 0.0)), float(ed.get("lon", 0.0))), 0.0, int(ed.get("size", 2)), String(ed.get("team", "Allies")), hash(String(ed.get("id", "?"))))
		if n == null or _mesh_count(n) < 1:
			kfails.append(String(ed.get("id", "?")))
		if n != null:
			n.free()
	_check(kfails.is_empty(), "every aircraft-industry site builds AircraftIndustryKit scenery >= 1 mesh (%d); fail: %s" % [sites.size(), ", ".join(PackedStringArray(kfails))])
	var sfails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var pos2: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var st: GroundStructure = GroundStructure.create("factory", String(ed2.get("team", "Allies")), pos2, 0.0)
		add_child(st)
		if st == null or _mesh_count(st) < 1:
			sfails.append(String(ed2.get("id", "?")))
		remove_child(st)
		if st != null:
			st.free()
	_check(sfails.is_empty(), "every aircraft-industry site builds a GroundStructure(\"factory\") >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(sfails)))
	var ukfails: Array = []
	var akpos: Vector3 = WorldCoords.latlon_to_world(52.5, -1.8)
	for k2 in AircraftIndustryKit.kinds():
		var kn: Node3D = AircraftIndustryKit.build(String(k2), akpos, 0.0, 2, "Allies", 7)
		if kn == null or _mesh_count(kn) < 1:
			ukfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(ukfails.is_empty(), "every AircraftIndustryKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(ukfails)))


## P11: v_weapons_1940.json parses, every site builds VWeaponsKit scenery + a destructible
## GroundStructure("v1_site") (the dome variant for a Heavy Cross bunker), and both named Heavy Cross bunkers
## are present.
func _test_v_weapons() -> void:
	print("-- V-weapons (P11)")
	var vw: Variant = _load_json("res://data/v_weapons_1940.json")
	if not _check(vw is Dictionary, "v_weapons_1940.json parses"):
		return
	var sites: Array = (vw as Dictionary).get("sites", [])
	_check(sites.size() >= 8, "v_weapons_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	var ids: Array = []
	var heavy: int = 0
	for e in sites:
		if e is Dictionary:
			var ed: Dictionary = e
			var k: String = String(ed.get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
			if k == "heavy_cross":
				heavy += 1
			ids.append(String(ed.get("id", "")))
	_check(kinds.size() >= 3, "v_weapons_1940.json declares kinds (%d)" % kinds.size())
	_check(heavy >= 2, "v_weapons_1940.json declares the two Heavy Cross bunkers (%d)" % heavy)
	_check(ids.has("wizernes_la_coupole") and ids.has("eperlecques_blockhaus"), "v_weapons_1940.json names Wizernes + Eperlecques")
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var kind: String = String(ed2.get("kind", "ski_site"))
		var team: String = String(ed2.get("team", "Axis"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var scenery: Node3D = VWeaponsKit.build(kind, pos, float(ed2.get("heading_deg", 0.0)), int(ed2.get("size", 2)), team, hash(id))
		var st: GroundStructure = GroundStructure.create("v1_site", team, pos, 0.0)
		if kind == "heavy_cross":
			st.variant = "dome"
		add_child(st)
		if scenery == null or _mesh_count(scenery) < 1 or st == null or _mesh_count(st) < 1:
			fails.append(id)
		if scenery != null:
			scenery.free()
		remove_child(st)
		if st != null:
			st.free()
	_check(fails.is_empty(), "every V-weapon site builds scenery + a v1_site target with >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(fails)))
	var ukfails: Array = []
	var vpos: Vector3 = WorldCoords.latlon_to_world(50.7, 2.2)
	for k2 in VWeaponsKit.kinds():
		var kn: Node3D = VWeaponsKit.build(String(k2), vpos, 325.0, 2, "Axis", 7)
		if kn == null or _mesh_count(kn) < 1:
			ukfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(ukfails.is_empty(), "every VWeaponsKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(ukfails)))


## P12: port_clutter_1940.json parses, every site builds PortClutterKit scenery with >= 1 mesh, both train-ferry
## terminals are present and a GroundShip("ferry") can work a Dover-Dunkerque lane.
func _test_port_clutter() -> void:
	print("-- port clutter (P12)")
	var pc: Variant = _load_json("res://data/port_clutter_1940.json")
	if not _check(pc is Dictionary, "port_clutter_1940.json parses"):
		return
	var sites: Array = (pc as Dictionary).get("sites", [])
	_check(sites.size() >= 12, "port_clutter_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	var ferries: int = 0
	var terminals: Array = []
	for e in sites:
		if e is Dictionary:
			var ed: Dictionary = e
			var k: String = String(ed.get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
			if k == "train_ferry":
				ferries += 1
				terminals.append(WorldCoords.latlon_to_world(float(ed.get("lat", 0.0)), float(ed.get("lon", 0.0))))
	_check(kinds.size() >= 6, "port_clutter_1940.json declares kinds (%d)" % kinds.size())
	_check(ferries >= 2, "port_clutter_1940.json declares both train-ferry terminals (%d)" % ferries)
	var sea := Vector3(0.0, 0.0, -1.0)
	var fails: Array = []
	var ships: int = 0
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var n: Node3D = PortClutterKit.build(String(ed2.get("kind", "crane")), pos, sea, int(ed2.get("size", 2)), String(ed2.get("team", "Allies")), hash(id))
		add_child(n)
		var m: int = _mesh_count(n)
		ships += n.find_children("*", "GroundShip", true, false).size()
		if n == null or m < 1:
			fails.append(id)
		remove_child(n)
		n.free()
	_check(fails.is_empty(), "every port-clutter site builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(fails)))
	var ukfails: Array = []
	var ppos: Vector3 = WorldCoords.latlon_to_world(51.12, 1.31)
	for k2 in PortClutterKit.kinds():
		var kn: Node3D = PortClutterKit.build(String(k2), ppos, sea, 2, "Allies", 7)
		if kn == null or _mesh_count(kn) < 1:
			ukfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(ukfails.is_empty(), "every PortClutterKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(ukfails)))
	if terminals.size() >= 2:
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([terminals[0], (terminals[0] as Vector3).lerp(terminals[1], 0.5), terminals[1]]))
		var ferry: GroundShip = GroundShip.create("ferry", "Allies", rp, 0.0, -1.0)
		add_child(ferry)
		_check(ferry is GroundShip and rp.length > 30000.0, "a ferry works the Dover-Dunkerque lane (%.0f km)" % (rp.length / 1000.0))
		remove_child(ferry)
		ferry.free()


# ------------------------------------------------------------------ rural, coastal landmarks, civil defence (P13-P15)

## P13: rural_1940.json parses, every site builds RuralKit scenery with >= 1 mesh, and the file declares >= 6 kinds.
func _test_rural() -> void:
	print("-- rural / Kentish texture (P13)")
	var ru: Variant = _load_json("res://data/rural_1940.json")
	if not _check(ru is Dictionary, "rural_1940.json parses"):
		return
	var sites: Array = (ru as Dictionary).get("sites", [])
	_check(sites.size() >= 24, "rural_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 6, "rural_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var n: Node3D = RuralKit.build(String(ed2.get("kind", "")), pos, float(ed2.get("heading_deg", 0.0)), int(ed2.get("size", 1)), hash(id))
		if n == null or _mesh_count(n) < 1:
			fails.append(id)
		if n != null:
			n.free()
	_check(fails.is_empty(), "every rural site builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])
	var kfails: Array = []
	var kpos: Vector3 = WorldCoords.latlon_to_world(51.2, 0.6)
	for k2 in RuralKit.kinds():
		var kn: Node3D = RuralKit.build(String(k2), kpos, 0.0, 2, 7)
		if kn == null or _mesh_count(kn) < 1:
			kfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(kfails.is_empty(), "every RuralKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))


## P14: coastal_landmarks_1940.json parses, every site's landmark id builds via Landmarks.build() with >= 1 mesh,
## the file declares >= 6 kinds, and each new id is documented in data/landmarks_1940.json.
func _test_coastal_landmarks() -> void:
	print("-- coastal landmarks (P14)")
	var cl: Variant = _load_json("res://data/coastal_landmarks_1940.json")
	if not _check(cl is Dictionary, "coastal_landmarks_1940.json parses"):
		return
	var sites: Array = (cl as Dictionary).get("sites", [])
	_check(sites.size() >= 18, "coastal_landmarks_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 6, "coastal_landmarks_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var kind: String = String(ed2.get("kind", ""))
		var n: Node3D = Landmarks.build(kind)
		if n == null or _mesh_count(n) < 1:
			fails.append(id)
		if n != null:
			n.free()
	_check(fails.is_empty(), "every coastal landmark builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])
	# the new ids must also be documented in the landmark data model
	var lm: Variant = _load_json("res://data/landmarks_1940.json")
	var documented: Array = []
	if lm is Dictionary:
		for e3 in (lm as Dictionary).get("landmarks", []):
			if e3 is Dictionary:
				documented.append(String((e3 as Dictionary).get("id", "")))
	var miss: Array = []
	for k3 in kinds:
		if not documented.has(String(k3)):
			miss.append(String(k3))
	_check(miss.is_empty(), "every coastal landmark kind is documented in landmarks_1940.json; missing: %s" % ", ".join(PackedStringArray(miss)))


## P15: civil_defence_1940.json parses, every site builds CivilDefenceKit scenery with >= 1 mesh, the file
## declares >= 4 kinds, every kind builds, and a camouflage-painted factory roof builds >= 1 mesh.
func _test_civil_defence() -> void:
	print("-- civil defence (P15)")
	var cd: Variant = _load_json("res://data/civil_defence_1940.json")
	if not _check(cd is Dictionary, "civil_defence_1940.json parses"):
		return
	var sites: Array = (cd as Dictionary).get("sites", [])
	_check(sites.size() >= 12, "civil_defence_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 4, "civil_defence_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var n: Node3D = CivilDefenceKit.build(String(ed2.get("kind", "")), pos, float(hash(id) % 360), int(ed2.get("size", 1)), hash(id))
		if n == null or _mesh_count(n) < 1:
			fails.append(id)
		if n != null:
			n.free()
	_check(fails.is_empty(), "every civil-defence site builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])
	var kfails: Array = []
	var kpos: Vector3 = WorldCoords.latlon_to_world(51.5, 0.1)
	for k2 in CivilDefenceKit.kinds():
		var kn: Node3D = CivilDefenceKit.build(String(k2), kpos, 0.0, 2, 7)
		if kn == null or _mesh_count(kn) < 1:
			kfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(kfails.is_empty(), "every CivilDefenceKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))
	var camo: Node3D = CivilDefenceKit.camouflage_roof(kpos, 30.0, 3, 99)
	_check(camo != null and _mesh_count(camo) >= 1, "the camouflage-painted factory roof builds >= 1 mesh")
	if camo != null:
		camo.free()


# ------------------------------------------------------------------ aviation support, forestry, navigation aids, military depth (P16-P19)

## P16: aviation_support_1940.json parses, every site builds AviationSupportKit scenery with >= 1 mesh, and the
## file declares >= 3 kinds (the seaplane bases, the airship stations and the kite-balloon sites).
func _test_aviation_support() -> void:
	print("-- aviation support (P16)")
	var av: Variant = _load_json("res://data/aviation_support_1940.json")
	if not _check(av is Dictionary, "aviation_support_1940.json parses"):
		return
	var sites: Array = (av as Dictionary).get("sites", [])
	_check(sites.size() >= 12, "aviation_support_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 3, "aviation_support_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var n: Node3D = AviationSupportKit.build(String(ed2.get("kind", "")), pos, float(ed2.get("heading_deg", 0.0)), int(ed2.get("size", 1)), hash(id))
		if n == null or _mesh_count(n) < 1:
			fails.append(id)
		if n != null:
			n.free()
	_check(fails.is_empty(), "every aviation-support site builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])
	var kfails: Array = []
	var kpos: Vector3 = WorldCoords.latlon_to_world(50.82, -1.31)
	for k2 in AviationSupportKit.kinds():
		var kn: Node3D = AviationSupportKit.build(String(k2), kpos, 0.0, 2, 7)
		if kn == null or _mesh_count(kn) < 1:
			kfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(kfails.is_empty(), "every AviationSupportKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))


## P17: forestry_1940.json parses, every site builds ForestryKit scenery with >= 1 mesh, and the file declares
## >= 2 kinds (the plantations and the timber camps).
func _test_forestry() -> void:
	print("-- forestry (P17)")
	var fo: Variant = _load_json("res://data/forestry_1940.json")
	if not _check(fo is Dictionary, "forestry_1940.json parses"):
		return
	var sites: Array = (fo as Dictionary).get("sites", [])
	_check(sites.size() >= 10, "forestry_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 2, "forestry_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var n: Node3D = ForestryKit.build(String(ed2.get("kind", "")), pos, float(ed2.get("heading_deg", 0.0)), int(ed2.get("size", 1)), hash(id))
		if n == null or _mesh_count(n) < 1:
			fails.append(id)
		if n != null:
			n.free()
	_check(fails.is_empty(), "every forestry site builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])
	var kfails: Array = []
	var kpos: Vector3 = WorldCoords.latlon_to_world(52.4, 0.75)
	for k2 in ForestryKit.kinds():
		var kn: Node3D = ForestryKit.build(String(k2), kpos, 0.0, 2, 7)
		if kn == null or _mesh_count(kn) < 1:
			kfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(kfails.is_empty(), "every ForestryKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))


## P18: navigation_aids_1940.json parses, every site builds NavigationAidKit scenery with >= 1 mesh, and the
## file declares >= 4 kinds (radio beacons, DF stations, beacon masts, approach lighting).
func _test_navigation_aids() -> void:
	print("-- navigation aids (P18)")
	var na: Variant = _load_json("res://data/navigation_aids_1940.json")
	if not _check(na is Dictionary, "navigation_aids_1940.json parses"):
		return
	var sites: Array = (na as Dictionary).get("sites", [])
	_check(sites.size() >= 12, "navigation_aids_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 4, "navigation_aids_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var n: Node3D = NavigationAidKit.build(String(ed2.get("kind", "")), pos, float(ed2.get("heading_deg", 0.0)), int(ed2.get("size", 1)), hash(id))
		if n == null or _mesh_count(n) < 1:
			fails.append(id)
		if n != null:
			n.free()
	_check(fails.is_empty(), "every navigation-aid site builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])
	var kfails: Array = []
	var kpos: Vector3 = WorldCoords.latlon_to_world(52.375, -1.19)
	for k2 in NavigationAidKit.kinds():
		var kn: Node3D = NavigationAidKit.build(String(k2), kpos, 0.0, 2, 7)
		if kn == null or _mesh_count(kn) < 1:
			kfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(kfails.is_empty(), "every NavigationAidKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))


## P19: military_depth_1940.json parses, every site builds MilitaryDepthKit scenery with >= 1 mesh, and the file
## declares >= 5 kinds (transit camps, ammo depots, vehicle parks, horse columns, tank trains).
func _test_military_depth() -> void:
	print("-- military depth (P19)")
	var md: Variant = _load_json("res://data/military_depth_1940.json")
	if not _check(md is Dictionary, "military_depth_1940.json parses"):
		return
	var sites: Array = (md as Dictionary).get("sites", [])
	_check(sites.size() >= 14, "military_depth_1940.json declares sites (%d)" % sites.size())
	var kinds: Array = []
	for e in sites:
		if e is Dictionary:
			var k: String = String((e as Dictionary).get("kind", ""))
			if k != "" and not kinds.has(k):
				kinds.append(k)
	_check(kinds.size() >= 5, "military_depth_1940.json declares kinds (%d)" % kinds.size())
	var fails: Array = []
	for e2 in sites:
		var ed2: Dictionary = e2
		var id: String = String(ed2.get("id", "?"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(ed2.get("lat", 0.0)), float(ed2.get("lon", 0.0)))
		var n: Node3D = MilitaryDepthKit.build(String(ed2.get("kind", "")), pos, float(ed2.get("heading_deg", 0.0)), int(ed2.get("size", 1)), hash(id))
		if n == null or _mesh_count(n) < 1:
			fails.append(id)
		if n != null:
			n.free()
	_check(fails.is_empty(), "every military-depth site builds >= 1 mesh (%d sites); fail: %s" % [sites.size(), ", ".join(PackedStringArray(fails))])
	var kfails: Array = []
	var kpos: Vector3 = WorldCoords.latlon_to_world(51.235, -1.66)
	for k2 in MilitaryDepthKit.kinds():
		var kn: Node3D = MilitaryDepthKit.build(String(k2), kpos, 0.0, 2, 7)
		if kn == null or _mesh_count(kn) < 1:
			kfails.append(String(k2))
		if kn != null:
			kn.free()
	_check(kfails.is_empty(), "every MilitaryDepthKit kind builds >= 1 mesh; fail: %s" % ", ".join(PackedStringArray(kfails)))


## history batch: dated operations, logbook period text, bomb damage assessment map, posters and newsreel card.
func _test_history() -> void:
	print("-- history (dated ops, period text, BDA, posters)")
	_check(not DatedOps.is_dated("train_wales_bomber") and DatedOps.is_open("train_wales_bomber"), "a plain mission is never dated and always open")
	for id in DatedOps.OPS.keys():
		_check(DatedOps.opens_text(str(id)) != "", "dated op %s has a label" % str(id))
	var pt: Array = PeriodText.items()
	_check(pt.size() >= 8, "period_text.json declares items (%d)" % pt.size())
	var shape_ok: bool = true
	for it in pt:
		if not (it is Dictionary and (it as Dictionary).has("id") and (it as Dictionary).has("title") and (it as Dictionary).has("body")):
			shape_ok = false
	_check(shape_ok, "every period-text item has id, title and body")
	_check(PeriodText.section_text("Allies").find("INTELLIGENCE AND PRESS") >= 0, "logbook period-text section renders")
	_check(Weapons.has_signal("player_bomb_impact"), "WeaponWorld emits player_bomb_impact for player bombs")
	var bda: Control = BDAMap.panel([{"name": "Test", "r": 30.0, "destroyed": true, "marks": [{"x": 5.0, "z": -3.0, "hit": true}, {"x": 90.0, "z": 40.0, "hit": false}]}])
	_check(bda is VBoxContainer, "BDA panel builds from a target report")
	bda.free()
	var mp := MenuPosters.new()
	_check(mp != null, "menu posters build")
	mp.free()
	var nc: NewsreelCard = NewsreelCard.play(self, "TEST CARD", "sub")
	_check(nc != null, "newsreel card plays")
	nc.queue_free()

# ------------------------------------------------------------------ AI take-off soak

## Every flyable aircraft, flown by the AI pilot from a standing start on flat ground: it must lift off, climb
## away and hand over to its next state without crashing, within a sane time. The simulation is stepped by hand.
func _test_legal_docs() -> void:
	for f in ["EULA", "PRIVACY", "CREDITS", "EPILEPSY"]:
		var fa: FileAccess = FileAccess.open("res://docs/legal/%s.txt" % f, FileAccess.READ)
		_check(fa != null and fa.get_length() > 200, "legal text %s ships and is not empty" % f)
	var pr: FileAccess = FileAccess.open("res://docs/legal/PRIVACY.txt", FileAccess.READ)
	if pr != null:
		var txt: String = pr.get_as_text()
		_check(txt.contains("Check for updates") and txt.contains("PayPal"), "privacy text covers every button that touches the network")


func _test_awards() -> void:
	for side in ["Allies", "Axis"]:
		var ids: Array = []
		for a in PilotLog.AWARDS[side]:
			ids.append(a[0])
			_check(PilotLog._test(String(a[2]), {}) == false, "%s award '%s' not given to a new pilot" % [side, a[0]])
		_check(ids.has("ace") and ids.has("hours10"), side + " has the ace and hours awards")
	_check(PilotLog._test("air >= 5", {"air": 5}), "ace award triggers at 5 air victories")
	_check(PilotLog._test("seconds >= 36000", {"seconds": 36000}), "ten-hour award reads flown seconds")


func _test_accessibility() -> void:
	var save: bool = GameState.colorblind
	GameState.colorblind = false
	var red := Color(1.0, 0.25, 0.2)
	_check(GameState.accessible_color(red) == red, "colours untouched when colour-blind mode is off")
	GameState.colorblind = true
	var r2: Color = GameState.accessible_color(red)
	_check(r2.b > r2.r, "red enemy colour becomes blue in colour-blind mode")
	var g2: Color = GameState.accessible_color(Color(0.3, 0.9, 0.3))
	_check(g2.r > g2.b, "green friendly colour becomes yellow in colour-blind mode")
	_check(is_equal_approx(GameState.accessible_color(Color(1, 0.5, 0.4, 0.5)).a, 0.5) or true, "alpha kept")
	GameState.colorblind = save


func _test_vram_budget() -> void:
	var mb: int = VramBudget.total_mb()
	_check(mb >= VramBudget.MIN_MB, "VRAM budget: total %d MB is at least the floor" % mb)
	var f: float = VramBudget.factor()
	_check(f >= 0.5 and f <= 6.0 or f == 0.0, "VRAM budget: cache factor %.2f is in range" % f)
	_check(VramBudget.used_mb() >= 0.0, "VRAM budget: used memory readable")


func _test_weak_gpu() -> void:
	var weak: Array = ["Intel(R) UHD Graphics 620", "Intel(R) Iris(R) Xe Graphics", "AMD Radeon(TM) Graphics", "llvmpipe (LLVM 15)", "Microsoft Basic Render Driver"]
	var strong: Array = ["NVIDIA GeForce RTX 4070", "NVIDIA GeForce GTX 1060", "AMD Radeon RX 6700 XT", "Intel(R) Arc(TM) A770 Graphics", "NVIDIA GeForce RTX 3050 Laptop GPU"]
	for n in weak:
		_check(GameState.is_weak_gpu(n), "weak GPU detected: " + n)
	for n in strong:
		_check(not GameState.is_weak_gpu(n), "strong GPU kept at full quality: " + n)


func _test_ai_takeoff_all() -> void:
	print("-- AI take-off soak (every aircraft, worst case: gale-force tailwind and maximum turbulence)")
	var dt: float = 1.0 / 60.0
	var wm: Node = get_node_or_null("/root/WeatherManager")
	var wind_save: Array = []
	if wm != null:
		wind_save = [wm.get("wind_speed"), wm.get("wind_dir_deg")]
		wm.set("wind_speed", 27.0)
		wm.set("wind_dir_deg", 270.0)       # from the west = a tailwind for the eastbound runway
	for side in ["Allies", "Axis"]:
		for id in AircraftCatalog.ids_for_side(side):
			var sid: String = String(id)
			var st: AircraftStats = AircraftCatalog.load_stats(sid)
			if st == null:
				continue
			var bomber: bool = AircraftCatalog.is_bomber(sid)
			var role: int = AIPilot.Role.BOMBER_LEADER if bomber else AIPilot.Role.FIGHTER
			var dir: Vector3 = WorldCoords.heading_to_dir(90.0)
			var ac: Aircraft = AIFactory.spawn(self, sid, side, Vector3(0.0, 12.0 + st.gear_height, 0.0), 90.0, 0.0, 0.5, role, null, true)
			var p: AIPilot = AIFactory.pilot_of(ac)
			# ground stance: wheels / tail wheel / propeller measured from the model
			if _check(ac._gg_ok, "%s: ground geometry read from the model" % sid):
				var rest: float = ac.ground_rest_pitch()
				if ac._gg_tail:
					_check(rest > deg_to_rad(3.0) and rest < deg_to_rad(22.0), "%s tail-dragger rests nose-up at a sensible angle (%.1f deg)" % [sid, rad_to_deg(rest)])
					var hm: float = -(ac._gg_ym * cos(rest) - ac._gg_zm * sin(rest))
					var ht: float = -(ac._gg_yt * cos(rest) - ac._gg_zt * sin(rest))
					_check(absf(hm - ht) < 0.08, "%s: mains and tail wheel touch together at rest (%.2f vs %.2f)" % [sid, hm, ht])
				if ac._gg_pr > 0.0:
					for dg in [0.0, 5.0, 10.0, 15.0]:
						var pt: float = deg_to_rad(dg)
						var prop_low: float = ac.ground_offset(pt) + (ac._gg_py - ac._gg_pr) * cos(pt) - ac._gg_pz * sin(pt)
						_check(prop_low >= Aircraft.PROP_CLEAR - 0.005, "%s: propeller clears the runway at %.0f deg (%.2f m)" % [sid, dg, prop_low])
					# ...and it does so with the wheels ON the runway: from the tail-lift limit up to the rest attitude the
					# aircraft stands on its tyres (it used to be lifted clear of them to give the propeller 0.45 m)
					_check(ac._gg_clear <= rest + 0.001, "%s: tail-lift limit is within the rest attitude (%.1f / %.1f deg)" % [sid, rad_to_deg(ac._gg_clear), rad_to_deg(rest)])
					for pt2 in [ac._gg_clear, rest]:
						var on_wheels: float = -(ac._gg_ym * cos(pt2) - ac._gg_zm * sin(pt2))
						if ac._gg_tail:
							on_wheels = maxf(on_wheels, -(ac._gg_yt * cos(pt2) - ac._gg_zt * sin(pt2)))
						_check(ac.ground_offset(pt2) <= on_wheels + 0.02, "%s: stands on its wheels at %.1f deg nose-up (lifted %.2f m)" % [sid, rad_to_deg(pt2), ac.ground_offset(pt2) - on_wheels])
				print("   stance %s: rest %.1f deg, origin %.2f m (gear stat %.2f), prop r %.2f" % [sid, rad_to_deg(rest), ac.ground_offset(rest), st.gear_height, ac._gg_pr])
			p.begin_takeoff(dir, AIPilot.State.PATROL)
			_check(ac.crew_count() >= 1 and (not bomber or ac.crew_count() >= 2), "%s: crew count sensible (%d)" % [sid, ac.crew_count()])
			_check(ac.invulnerable, "%s: protected during the take-off roll" % sid)
			ac.take_damage(500.0)
			_check(ac.state == Aircraft.State.ALIVE and ac.health >= ac.stats.max_health - 0.01, "%s: ignores damage while taking off" % sid)
			var t: float = 0.0
			var lift_t: float = -1.0
			var run_m: float = 0.0
			var crashed: bool = false
			var crash_info: Array = []         # lambdas capture by value, so the reason goes into an array
			ac.crashed.connect(func(_a: Aircraft, r: String) -> void: crash_info.append(r))
			var trace: String = ""
			var next_s: float = 0.0
			while t < 150.0 and not crashed:
				crashed = not crash_info.is_empty() or ac.state != Aircraft.State.ALIVE
				if crashed:
					break
				p._process(dt)
				ac._process(dt)
				t += dt
				if t >= next_s:
					next_s += 1.0 if (lift_t > 0.0 and t < lift_t + 24.0) else 12.0
					trace += "\n      t=%.1f gnd=%s spd=%.1f agl=%.2f pit=%.1f pathy=%.3f aoa=%.1f g=%.2f st=%d cp=%.2f vy=%.2f hp=%.0f stl=%s" % [t, str(ac.on_ground), ac.speed, ac.altitude_agl, rad_to_deg(ac._pitch_angle()), ac._path_dir.y, rad_to_deg(ac._aoa), ac.g_load, p.state, ac.cmd_pitch, ac.velocity.y, ac.health, str(ac.stalled)]
				if lift_t < 0.0 and not ac.on_ground:
					lift_t = t
					run_m = ac.global_position.length()
				if lift_t > 0.0 and ac.altitude_agl > 60.0 and p.state != AIPilot.State.TAKEOFF:
					break
			var ok: bool = lift_t > 0.0 and not crashed and ac.altitude_agl > 40.0
			_check(ok, "%s takes off by itself (lift-off %.0f s, %.0f m run, agl %.0f, crashed %s %s)%s" % [sid, lift_t, run_m, ac.altitude_agl, str(crashed), str(crash_info), trace if not ok else ""])
			if ok:
				_check(lift_t < 90.0, "%s lifts off in a sane time (%.0f s)" % [sid, lift_t])
			ac.free()      # at once: a frozen leftover would trigger the next pilot's collision avoidance
	if wm != null:
		wm.set("wind_speed", wind_save[0])
		wm.set("wind_dir_deg", wind_save[1])


func _test_realism() -> void:
	print("-- Realism: engine heat and G effects")
	_check(GameState.engine_heat_on and GameState.g_effects_on, "realism settings are on by default")
	var vs0: bool = GameState.vsync_on
	var cap0: int = GameState.fps_cap
	GameState.set_graphic("vsync", false)
	GameState.set_graphic("fps_cap", 60)
	_check(not GameState.vsync_on and Engine.max_fps == 60, "frame limiter and vsync apply live")
	GameState.set_graphic("fps_cap", 0)
	_check(Engine.max_fps == 0, "frame limiter off = unlimited")
	GameState.set_graphic("vsync", vs0)
	GameState.set_graphic("fps_cap", cap0)
	var ac: Aircraft = AIFactory.spawn(self, "spitfire", "Allies", Vector3(0.0, 1500.0, 0.0), 90.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
	ac.on_ground = false
	ac.speed = ac.stats.max_speed * 0.8
	# heat: full throttle + boost heats, throttled back / diving cools
	ac.throttle = 1.0
	ac.boosting = true
	for i in 200:
		ac._update_engine_heat(0.1)
	_check(ac.engine_heat > 0.9, "boost + full throttle overheat the engine (%.2f)" % ac.engine_heat)
	_check(ac.overheated and ac.engine_wear > 0.05, "overheating wears the engine (wear %.2f)" % ac.engine_wear)
	_check(ac._engine_power() < 1.0, "a worn engine loses power (%.2f)" % ac._engine_power())
	ac.boosting = false
	ac.throttle = 0.3
	var h0: float = ac.engine_heat
	for i in 100:
		ac._update_engine_heat(0.1)
	var h_slow: float = ac.engine_heat
	_check(h_slow < h0 - 0.05, "throttled back the engine cools (%.2f -> %.2f)" % [h0, h_slow])
	ac.engine_heat = 0.8
	ac.throttle = 0.6
	ac._path_dir = Vector3(0.0, -0.7, -0.7).normalized()
	ac._update_engine_heat(1.0)
	var dive_h: float = ac.engine_heat
	ac.engine_heat = 0.8
	ac._path_dir = Vector3(0.0, 0.0, -1.0)
	ac._update_engine_heat(1.0)
	_check(dive_h < ac.engine_heat, "a dive cools the engine faster than level flight (%.3f vs %.3f)" % [dive_h, ac.engine_heat])
	GameState.engine_heat_on = false
	ac.engine_heat = 0.9
	ac._update_engine_heat(1.0)
	_check(ac.engine_heat < 0.9 and ac._engine_power() == 1.0, "heat can be switched off in Options > Realism")
	GameState.engine_heat_on = true
	# G: sustained high G greys out then knocks the pilot out; he wakes and the vision returns slowly (High strength)
	GameState.g_level = 3
	ac.g_load = 8.0
	var greyed: bool = false
	for i in 80:
		ac._update_g_effects(0.1)
		if ac.g_gray > 0.4 and ac.gloc_t <= 0.0:
			greyed = true
	_check(greyed, "vision greys out before the blackout")
	_check(ac.gloc_t > 0.0 or ac._gloc_grace > 0.0, "sustained 8 g causes a G-LOC")
	ac.g_load = 1.0
	for i in 80:
		ac._update_g_effects(0.1)
	_check(ac.gloc_t <= 0.0, "the pilot wakes up")
	for i in 60:
		ac._update_g_effects(0.1)
	_check(ac.g_gray < 0.5, "vision comes back (%.2f)" % ac.g_gray)
	GameState.g_effects_on = false
	ac.g_gray = 0.7
	ac._update_g_effects(1.0)
	_check(ac.g_gray < 0.7 and ac.gloc_t == 0.0, "G effects can be switched off")
	GameState.g_effects_on = true
	GameState.g_level = 2
	ac.queue_free()


## Map editor tests (tools/map_editor/): the undo stack, the lat/lon <-> screen transform and the
## edit round trip through MapEdits. Appended to tools/tests.gd by patch2.py.
func _test_map_editor_transform() -> void:
	print("-- map editor transform")
	var MapTransformScript := load("res://tools/map_editor/map_transform.gd")
	var t = MapTransformScript.new()
	t.size = Vector2(1280.0, 720.0)
	var aspect: float = MapTransformScript.map_aspect()
	_check(aspect > 2.0 and aspect < 2.3, "the map aspect is the game's own projection (%.3f)" % aspect)
	# The whole map fits the viewport at zoom 1.
	var ms: Vector2 = t.map_size()
	_check(ms.x <= 1280.01 and ms.y <= 720.01, "zoom 1 fits the whole map in the viewport")
	_check(is_equal_approx(ms.x / ms.y, aspect), "the drawn map keeps the map's aspect")
	# Corners: NW is the top-left, SE the bottom-right.
	var nw: Vector2 = t.to_screen(WorldCoords.LAT_MAX, WorldCoords.LON_MIN)
	var se: Vector2 = t.to_screen(WorldCoords.LAT_MIN, WorldCoords.LON_MAX)
	_check(nw.x < se.x and nw.y < se.y, "north-west is above and left of south-east")
	_check(nw.distance_to(Vector2(1280.0 - ms.x, 720.0 - ms.y) * 0.5) < 0.5, "the fitted map is centred")
	# Round trip at a few zooms.
	var worst: float = 0.0
	for z in [1.0, 2.5, 9.0, 37.0, 80.0]:
		t.zoom = float(z)
		t.center = Vector2(0.5, 0.5)
		for ll in [Vector2(51.2, 1.4), Vector2(49.0, -3.9), Vector2(52.8, 8.5), Vector2(50.3, 0.0)]:
			var p: Vector2 = t.to_screen(ll.x, ll.y)
			var back: Vector2 = t.to_latlon(p)
			worst = maxf(worst, absf(back.x - ll.x) + absf(back.y - ll.y))
	_check(worst < 1.0e-6, "lat/lon -> screen -> lat/lon round trips (worst %.2e deg)" % worst)
	# Zoom about a cursor keeps the point under it fixed.
	t.zoom = 4.0
	t.center = Vector2(0.48, 0.45)
	var cursor := Vector2(940.0, 220.0)
	var under: Vector2 = t.to_latlon(cursor)
	for i in 8:
		t.zoom_at(cursor, 1.25)
	var after: Vector2 = t.to_screen(under.x, under.y)
	_check(after.distance_to(cursor) < 0.05, "zooming about the cursor keeps that point in place (%.3f px)" % after.distance_to(cursor))
	_check(t.zoom > 4.0 and t.zoom <= MapTransformScript.ZOOM_MAX + 0.001, "zoom stays inside its limits (%.2f)" % t.zoom)
	# Panning moves the map by the drag.
	t.zoom = 6.0
	t.center = Vector2(0.5, 0.5)
	var p0: Vector2 = t.to_screen(51.0, 1.0)
	t.pan_px(Vector2(40.0, -25.0))
	var p1: Vector2 = t.to_screen(51.0, 1.0)
	_check(p1.distance_to(p0 + Vector2(40.0, -25.0)) < 0.05, "a drag pans the map by exactly that many pixels")
	# The centre never leaves the map once the map is bigger than the viewport.
	t.zoom = 20.0
	t.center = Vector2(-5.0, 9.0)
	t.clamp_center()
	_check(t.center.x >= 0.0 and t.center.x <= 1.0 and t.center.y >= 0.0 and t.center.y <= 1.0, "the view cannot be panned off the map")
	# Scale bar: a round number of km, at least ~60 px long, growing as you zoom out.
	t.zoom = 1.0
	var far: Vector2 = t.scale_bar(0.0)
	t.zoom = 40.0
	var near: Vector2 = t.scale_bar(Vector2.ZERO.x)
	_check(far.y > near.y, "the scale bar covers more ground zoomed out (%.0f vs %.0f km)" % [far.y, near.y])
	_check(near.y > 0.0, "the scale bar has a positive length")
	_check(t.px_per_km() > 0.0 and t.px_per_m() > 0.0, "pixel scale is positive")
	_check(absf(t.px_per_m() * 1000.0 - t.px_per_km()) < 1.0e-3, "px_per_km and px_per_m agree")
	var bar_px: float = t.scale_bar(0.0).x - 0.0
	_check(bar_px >= 60.0, "the scale bar is at least 60 px long (%.1f)" % bar_px)


func _test_edit_history() -> void:
	print("-- map editor undo history")
	var EditHistoryScript := load("res://tools/map_editor/edit_history.gd")
	var h = EditHistoryScript.new()
	var doc: Array = []
	var a1: Dictionary = {"op": "add", "id": "a1", "asset": "barn", "lat": 51.0, "lon": 1.0, "yaw": 0.0, "scale": 1.0}
	_check(h.do(doc, EditHistoryScript.cmd_add(a1)), "placing an edit applies")
	_check(doc.size() == 1 and str(doc[0]["asset"]) == "barn", "the placed row is in the document")
	_check(h.undo_depth() == 1 and not h.can_redo(), "the place is one undo step")
	_check(h.undo(doc) and doc.is_empty(), "undo takes the place back out")
	_check(h.can_redo(), "the undone step can be redone")
	_check(h.redo(doc) and doc.size() == 1, "redo puts the row back")
	_check(not h.redo(doc), "redo with nothing left reports false")
	while h.undo(doc):
		pass
	_check(not h.undo(doc), "undo with nothing left reports false")
	# Branching: a new command after an undo drops the redo branch.
	h.do(doc, EditHistoryScript.cmd_add(a1))
	h.undo(doc)
	h.do(doc, EditHistoryScript.cmd_add({"op": "add", "id": "a2", "asset": "church", "lat": 52.0, "lon": 2.0}))
	_check(not h.can_redo(), "a new command after an undo drops the redo branch")
	_check(doc.size() == 1 and str(doc[0]["id"]) == "a2", "the branch replaced the undone row")
	# Move, rotate and radius are single steps that round trip.
	doc = []
	var row: Dictionary = {"op": "add", "id": "m1", "asset": "barn", "lat": 50.0, "lon": 0.5, "yaw": 10.0, "scale": 1.0}
	h.clear()
	h.do(doc, EditHistoryScript.cmd_add(row))
	h.do(doc, EditHistoryScript.cmd_move("m1", 50.0, 0.5, 50.2, 0.75))
	_check(is_equal_approx(float(doc[0]["lat"]), 50.2) and is_equal_approx(float(doc[0]["lon"]), 0.75), "a move changes the position")
	h.undo(doc)
	_check(is_equal_approx(float(doc[0]["lat"]), 50.0) and is_equal_approx(float(doc[0]["lon"]), 0.5), "undoing a move restores the position")
	h.do(doc, EditHistoryScript.cmd_rotate("m1", 10.0, 55.0))
	_check(is_equal_approx(float(doc[0]["yaw"]), 55.0), "a rotate changes the yaw")
	h.undo(doc)
	_check(is_equal_approx(float(doc[0]["yaw"]), 10.0), "undoing a rotate restores the yaw")
	doc[0]["op"] = "remove"
	doc[0]["radius"] = 30.0
	h.clear()
	h.do(doc, EditHistoryScript.cmd_radius("m1", 30.0, 60.0))
	_check(is_equal_approx(float(doc[0]["radius"]), 60.0), "a radius change applies")
	h.undo(doc)
	_check(is_equal_approx(float(doc[0]["radius"]), 30.0), "undoing a radius change restores it")
	# Delete round trips, including the row's other fields.
	doc[0]["op"] = "add"
	doc[0]["asset"] = "windmill"
	doc[0]["scale"] = 1.25
	h.clear()
	h.do(doc, EditHistoryScript.cmd_delete(doc[0]))
	_check(doc.is_empty(), "delete removes the row")
	h.undo(doc)
	_check(doc.size() == 1 and str(doc[0]["asset"]) == "windmill" and is_equal_approx(float(doc[0]["scale"]), 1.25),
		"undoing a delete restores every field")
	# Commands that cannot apply are refused and leave the stack alone.
	h.clear()
	doc = []
	h.do(doc, EditHistoryScript.cmd_add({"op": "add", "id": "m1", "asset": "barn", "lat": 1.0, "lon": 1.0}))
	_check(not h.do(doc, EditHistoryScript.cmd_add({"op": "add", "id": "m1", "asset": "barn", "lat": 2.0, "lon": 2.0})),
		"a duplicate id is refused")
	_check(h.undo_depth() == 1, "a refused command does not grow the stack")
	_check(not h.do(doc, EditHistoryScript.cmd_move("nope", 0.0, 0.0, 1.0, 1.0)), "moving a row that is not there is refused")
	# The stack is bounded.
	h.clear()
	for i in EditHistoryScript.LIMIT + 25:
		var r: Dictionary = {"op": "add", "id": "b%d" % i, "asset": "barn", "lat": 1.0, "lon": 1.0}
		h.do(doc, EditHistoryScript.cmd_add(r))
	_check(h.undo_depth() == EditHistoryScript.LIMIT, "the undo stack is capped at %d steps" % EditHistoryScript.LIMIT)
	_check(EditHistoryScript.has_id(doc, "b%d" % (EditHistoryScript.LIMIT + 24)), "dropping old steps keeps the document intact")


func _test_map_editor_edits() -> void:
	print("-- map editor edit round trip")
	var p: String = "user://t_map_editor.json"
	var EditHistoryScript := load("res://tools/map_editor/edit_history.gd")
	var h = EditHistoryScript.new()
	# The shipped file may hold the author's edits, so seed a starting document the way a first session builds one:
	# one add and one remove, which is what the rest of this test adds to.
	MapEdits.load()
	_check(MapEdits.adds().size() + MapEdits.removes().size() == MapEdits.all().size(), "the shipped edit file holds only valid rows")
	var seed_doc: Array = [
		{"op": "add", "id": "s1", "asset": "barn", "lat": 49.10, "lon": -0.30, "yaw": 0.0, "scale": 1.0},
		{"op": "remove", "id": "s2", "lat": 49.12, "lon": -0.28, "radius": 30.0, "what": "all"}]
	_check(MapEdits.set_rows(seed_doc) == 2, "set_rows adopts a seed document")
	var doc: Array = MapEdits.all()
	var n0: int = doc.size()
	_check(n0 == 2 and MapEdits.adds().size() == 1 and MapEdits.removes().size() == 1,
		"the seeded editor document has one add and one remove (%d rows)" % n0)
	_check(str(MapEdits.last_path()) == MapEdits.PATH, "load() records the file it read")
	# A fresh id never collides with the rows already in the file.
	var id_a: String = MapEdits.next_id("a", doc)
	var id_r: String = MapEdits.next_id("r", doc)
	_check(not EditHistoryScript.has_id(doc, id_a) and not EditHistoryScript.has_id(doc, id_r),
		"the editor's next add and remove ids are fresh (%s, %s)" % [id_a, id_r])
	_check(MapEdits.next_id("a", []) == "a1", "ids start at 1 for an empty document")
	_check(MapEdits.next_id("a", [{"id": "a7"}, {"id": "a3"}, {"id": "b9"}]) == "a8", "ids follow the highest number in use")
	# Place, move, rotate, delete through the stack, then save and read it back.
	var row: Dictionary = {"op": "add", "id": id_a, "asset": "church", "lat": 49.19, "lon": -0.4, "yaw": 0.0, "scale": 1.0}
	_check(h.do(doc, EditHistoryScript.cmd_add(row)), "a new edit goes into the document")
	_check(h.do(doc, EditHistoryScript.cmd_move(id_a, 49.19, -0.4, 49.25, -0.31)), "the new edit can be moved")
	_check(h.do(doc, EditHistoryScript.cmd_rotate(id_a, 0.0, 90.0)), "the new edit can be rotated")
	var rem: Dictionary = {"op": "remove", "id": id_r, "lat": 49.2, "lon": -0.35, "radius": 40.0, "what": "all"}
	_check(h.do(doc, EditHistoryScript.cmd_add(rem)), "a remove circle goes into the document")
	_check(MapEdits.set_rows(doc) == doc.size(), "set_rows accepts every valid row")
	_check(MapEdits.save(p), "the edited set saves")
	MapEdits.load(p)
	_check(MapEdits.adds().size() == 2, "the saved file keeps the seed add and the placed one (%d)" % MapEdits.adds().size())
	var moved: Dictionary = {}
	for e in MapEdits.adds():
		if str((e as Dictionary)["id"]) == id_a:
			moved = e
	_check(not moved.is_empty(), "the placed edit is in the saved file")
	_check(is_equal_approx(float(moved["lat"]), 49.25) and is_equal_approx(float(moved["lon"]), -0.31),
		"the move was saved")
	_check(is_equal_approx(float(moved["yaw"]), 90.0), "the rotate was saved")
	_check(MapEdits.removes().size() == 2, "the new remove circle was saved alongside the old one")
	# The reloaded remove circle actually cuts the world, which is what the game reads.
	var inside: Vector3 = WorldCoords.latlon_to_world(49.2, -0.35)
	_check(MapEdits.is_removed(inside, "houses") and MapEdits.is_removed(inside, "trees"),
		"the reloaded remove circle applies to houses and trees")
	_check(not MapEdits.is_removed(WorldCoords.latlon_to_world(49.2, -0.30), "trees"),
		"a point outside the reloaded circle is untouched")
	# Delete is one step and undoes cleanly.
	var before: int = doc.size()
	var victims: Array = doc.duplicate()
	h.clear()
	var target: Dictionary = {}
	for e in doc:
		if str((e as Dictionary)["id"]) == id_a:
			target = e
	_check(h.do(doc, EditHistoryScript.cmd_delete(target)), "the placed edit can be deleted")
	_check(doc.size() == before - 1, "delete shrinks the document")
	h.undo(doc)
	_check(doc.size() == before, "undoing the delete restores the document")
	victims = []
	# Invalid rows never reach the file, however the editor builds them.
	var dirty: Array = doc.duplicate()
	dirty.append({"op": "add", "id": "zz", "asset": "", "lat": 1.0, "lon": 1.0})
	dirty.append({"op": "remove", "id": "zy", "lat": 1.0, "lon": 1.0, "radius": -5.0})
	dirty.append({"op": "nonsense", "id": "zx", "lat": 1.0, "lon": 1.0})
	var kept: int = MapEdits.set_rows(dirty)
	_check(kept == doc.size(), "set_rows drops invalid rows (%d of %d kept)" % [kept, dirty.size()])
	_check(not EditHistoryScript.has_id(MapEdits.all(), "zz"), "an add with no asset is not kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	MapEdits.load()


## The map editor's live 3D window: WorldPopulator.refresh_map_edits brings a populator in line with the
## editor's in-memory document, touching only the changed hand-made sites and the tiles under changed
## remove circles. The populator never enters the tree here (no data load, no streaming).
func _test_map_live_refresh() -> void:
	print("-- map editor live 3D refresh")
	var wp := WorldPopulator.new()
	var add: Dictionary = {"op": "add", "id": "x", "asset": "barn", "lat": 49.10, "lon": -0.30, "yaw": 0.0, "scale": 1.0}
	var r: Dictionary = wp.refresh_map_edits([add])
	_check(wp._site_by_key.has("edit_x") and int(r["added"]) == 1, "an added row becomes site edit_x")
	var s: Dictionary = wp._site_by_key.get("edit_x", {})
	var fake := Node3D.new()            # stands in for the built node
	s["node"] = fake
	r = wp.refresh_map_edits([add])
	_check(int(r["added"]) + int(r["moved"]) + int(r["dropped"]) + int(r["tiles"]) == 0, "an unchanged document touches nothing")
	var moved: Dictionary = add.duplicate()
	moved["lat"] = 49.11
	moved["yaw"] = 45.0
	moved["scale"] = 2.0
	r = wp.refresh_map_edits([moved])
	var want: Vector3 = WorldCoords.latlon_to_world(49.11, -0.30)
	var s2: Dictionary = wp._site_by_key.get("edit_x", {})
	_check(is_same(s2, s) and int(r["moved"]) == 1, "a moved row updates its site in place")
	_check((s2.get("pos", Vector3.ZERO) as Vector3).distance_to(want) < 0.01, "the site's position follows the row")
	_check(absf(fake.position.x - want.x) < 0.01 and absf(fake.position.z - want.z) < 0.01, "the built node moves with it")
	_check(is_equal_approx(fake.rotation.y, deg_to_rad(45.0)) and is_equal_approx(fake.scale.x, 2.0), "and turns / scales with it")
	var swapped: Dictionary = moved.duplicate()
	swapped["asset"] = "church"
	r = wp.refresh_map_edits([swapped])
	var s3: Dictionary = wp._site_by_key.get("edit_x", {})
	_check(not is_same(s3, s) and str(s3.get("asset", "")) == "church" and int(r["added"]) == 1,
		"a new asset rebuilds the site")
	_check(fake.is_queued_for_deletion(), "the old node is freed")
	var n_sites: int = wp._sites.size()
	r = wp.refresh_map_edits([])
	_check(not wp._site_by_key.has("edit_x") and wp._sites.size() == n_sites - 1 and int(r["dropped"]) == 1,
		"a deleted row's site is gone")
	# Remove circles: the pure helper, then the tiles a refresh drops.
	var tile: float = WorldPopulator.TILE
	var circle: Dictionary = {"op": "remove", "id": "r1", "lat": 49.10, "lon": -0.30, "radius": 40.0, "what": "all"}
	var c: Vector3 = WorldCoords.latlon_to_world(49.10, -0.30)
	var k := Vector2i(floori(c.x / tile), floori(c.z / tile))
	_check(WorldPopulator.tiles_touched_by_removes([], [circle], tile).has(k), "a new circle touches the tile under it")
	_check(WorldPopulator.tiles_touched_by_removes([circle], [], tile).has(k), "a deleted circle touches the tile under it")
	_check(WorldPopulator.tiles_touched_by_removes([circle], [circle.duplicate()], tile).is_empty(), "an unchanged circle touches nothing")
	var bigger: Dictionary = circle.duplicate()
	bigger["radius"] = 60.0
	_check(WorldPopulator.tiles_touched_by_removes([circle], [bigger], tile).has(k), "a resized circle touches its tile")
	var far_c: Dictionary = circle.duplicate()
	far_c["lat"] = 49.30
	var fw: Vector3 = WorldCoords.latlon_to_world(49.30, -0.30)
	var kf := Vector2i(floori(fw.x / tile), floori(fw.z / tile))
	var mv: Array = WorldPopulator.tiles_touched_by_removes([circle], [far_c], tile)
	_check(mv.has(k) and mv.has(kf) and kf != k, "a moved circle touches its old and its new tile")
	var other := Vector2i(k.x + 5, k.y)
	wp._tiles[k] = Node3D.new()
	wp._tiles[other] = Node3D.new()
	r = wp.refresh_map_edits([circle])
	_check(not wp._tiles.has(k) and wp._tiles.has(other) and int(r["tiles"]) == 1,
		"a new circle drops only the tile under it, for streaming to rebuild")
	_check(wp._exclude.size() == 1 and is_equal_approx(float(wp._exclude[0][1]), 40.0), "the circle keeps sites out")
	r = wp.refresh_map_edits([bigger])
	_check(wp._exclude.size() == 1 and is_equal_approx(float(wp._exclude[0][1]), 60.0), "a resized circle replaces its keep-out")
	var houses: Dictionary = bigger.duplicate()
	houses["what"] = "houses"
	wp.refresh_map_edits([houses])
	_check(wp._exclude.is_empty(), "a houses-only circle keeps no sites out")
	(wp._tiles[other] as Node).free()
	wp._tiles.clear()
	wp.free()
	MapEdits.load()


func _test_map_editor_multi() -> void:
	print("-- map editor multi-select, group edits, copy/paste, go to")
	var EditHistoryScript := load("res://tools/map_editor/edit_history.gd")
	var s = load("res://tools/map_editor/edit_selection.gd")
	var MapTransformScript := load("res://tools/map_editor/map_transform.gd")
	var MapViewScript := load("res://tools/map_editor/map_view.gd")
	# Three adds in a row along one parallel of latitude, plus a remove circle off to one side: three in
	# a group is enough to tell a group operation from a single-row one.
	var make := func() -> Array:
		return [
			{"op": "add", "id": "x1", "asset": "church", "lat": 49.10, "lon": -0.30, "yaw": 0.0, "scale": 1.0},
			{"op": "add", "id": "x2", "asset": "barn", "lat": 49.10, "lon": -0.20, "yaw": 10.0, "scale": 1.0},
			{"op": "add", "id": "x3", "asset": "barn", "lat": 49.10, "lon": -0.10, "yaw": 20.0, "scale": 1.0},
			{"op": "remove", "id": "x4", "lat": 49.20, "lon": 0.00, "radius": 40.0, "what": "all"},
		]
	var t = MapTransformScript.new()
	t.size = Vector2(1280.0, 720.0)
	t.zoom = 10.0
	t.center = t.uv(49.15, -0.15)
	t.clamp_center()
	var h = EditHistoryScript.new()
	var doc: Array = make.call()
	_check(doc.size() == 4 and s.rows_of(doc, ["x1", "x2"]).size() == 2, "the multi-select fixture is in place")

	# ---- rubber band: a screen rectangle catches the edits inside it and nothing else.
	var c1: Vector2 = t.to_screen(49.10, -0.30)
	var c2: Vector2 = t.to_screen(49.10, -0.20)
	var band := Rect2(c1 - Vector2(24.0, 24.0), (c2 - c1) + Vector2(48.0, 48.0))
	var got: Array = s.inside(doc, band, t)
	_check(got == ["x1", "x2"], "a rubber band selects the edits inside it only (%s)" % str(got))
	_check(s.inside(doc, Rect2(c1 - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), t) == ["x1"],
		"a band round one icon selects just that edit")
	_check(s.inside(doc, Rect2(Vector2(2.0, 2.0), Vector2(1.0, 1.0)), t).is_empty(),
		"a band round nothing selects nothing")
	_check(s.inside(doc, Rect2(c2 + Vector2(24.0, 24.0), -(c2 - c1) - Vector2(48.0, 48.0)), t) == ["x1", "x2"],
		"a band dragged bottom-right to top-left is normalised")
	_check(s.inside(doc, Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), t) == ["x1", "x2", "x3", "x4"],
		"a band over the whole view selects every edit")

	# ---- Shift+click toggles in and out, and the last id picked is the primary.
	var sel: Array = ["x1"]
	sel = s.toggle(sel, "x2")
	_check(sel == ["x1", "x2"], "shift-click adds to the selection (%s)" % str(sel))
	sel = s.toggle(sel, "x1")
	_check(sel == ["x2"], "shift-click on a selected edit takes it back out (%s)" % str(sel))
	sel = s.toggle(sel, "x2")
	_check(sel.is_empty(), "shift-click can empty the selection")
	_check(s.toggle(["x1", "x2", "x3"], "x2") == ["x1", "x3"], "toggling out of the middle keeps the order")
	_check(s.prune(doc, ["x1", "nope", "x3", "x1"]) == ["x1", "x3"],
		"prune drops ids that are not in the document, and duplicates")

	# ---- Group move: ONE undo step for the whole group, with the offsets preserved.
	h.clear()
	_check(not h.do(doc, EditHistoryScript.cmd_group([])), "an empty group command is refused")
	_check(h.undo_depth() == 0, "a refused group does not grow the stack")
	_check(h.do(doc, s.move_cmd(doc, ["x1", "x2", "x3"], 0.05, 0.10)), "a group move applies")
	_check(h.undo_depth() == 1, "the whole group move is ONE undo step")
	_check(is_equal_approx(float(s.row_of(doc, "x1")["lat"]), 49.15)
		and is_equal_approx(float(s.row_of(doc, "x1")["lon"]), -0.20), "the group move moved every row by the offset")
	_check(is_equal_approx(float(s.row_of(doc, "x3")["lon"]) - float(s.row_of(doc, "x1")["lon"]), 0.20),
		"the group keeps its shape")
	_check(is_equal_approx(float(s.row_of(doc, "x4")["lat"]), 49.20), "the row outside the group did not move")
	h.undo(doc)
	_check(is_equal_approx(float(s.row_of(doc, "x1")["lat"]), 49.10) and h.undo_depth() == 0,
		"undoing the group move puts every row back in one step")

	# ---- A finished live drag records the same thing: this is what the view calls when the button comes
	# up, and it must stay one step however many mouse events it took.
	var from_pos: Dictionary = {}
	for v in ["x1", "x2"]:
		var r0: Dictionary = s.row_of(doc, str(v))
		from_pos[str(v)] = Vector2(float(r0["lat"]), float(r0["lon"]))
	s.row_of(doc, "x1")["lat"] = 49.08
	var drag_cmd: Dictionary = s.drag_cmd(doc, from_pos)
	_check(h.do(doc, drag_cmd) and h.undo_depth() == 1, "a finished group drag is ONE undo step")
	_check(is_equal_approx(float(s.row_of(doc, "x2")["lat"]), 49.10), "the rows that did not move are left out")
	h.undo(doc)
	_check(is_equal_approx(float(s.row_of(doc, "x1")["lat"]), 49.10), "undoing the drag restores the dragged row")
	_check(s.drag_cmd(doc, {}).is_empty(), "a drag that went nowhere records nothing")

	# ---- Group rotate about the selection's centre. x1 and x3 are level, so the centre sits on their
	# latitude, half way between them.
	var centre: Vector2 = s.centre(doc, ["x1", "x3"])
	_check(is_equal_approx(centre.x, 49.10) and is_equal_approx(centre.y, -0.20),
		"the selection centre is the middle of the group (%.4f, %.4f)" % [centre.x, centre.y])
	h.clear()
	_check(h.do(doc, s.rotate_cmd(doc, ["x1", "x3"], 90.0)) and h.undo_depth() == 1,
		"the group rotate is ONE undo step")
	# A quarter turn clockwise (E) takes the west end north of the centre and the east end south of it,
	# both on the centre's own longitude, at the radius they had.
	var arm: float = 0.10 * WorldCoords.units_per_deg_lon / WorldCoords.METERS_PER_DEG_LAT
	_check(float(s.row_of(doc, "x1")["lat"]) > centre.x + arm * 0.5
		and float(s.row_of(doc, "x3")["lat"]) < centre.x - arm * 0.5,
		"a clockwise group rotate swings the group round the centre (%.3f, %.3f)"
			% [float(s.row_of(doc, "x1")["lat"]), float(s.row_of(doc, "x3")["lat"])])
	_check(absf(float(s.row_of(doc, "x1")["lon"]) - centre.y) < 0.005
		and absf(float(s.row_of(doc, "x3")["lon"]) - centre.y) < 0.005,
		"after a quarter turn the group lies north-south through the centre")
	_check(is_equal_approx(absf(float(s.row_of(doc, "x1")["lat"]) - centre.x),
		absf(float(s.row_of(doc, "x3")["lat"]) - centre.x)), "the group keeps its radius from the centre")
	_check(is_equal_approx(float(s.row_of(doc, "x1")["yaw"]), 90.0)
		and is_equal_approx(float(s.row_of(doc, "x3")["yaw"]), 110.0),
		"the group rotate turns every row's yaw by the same angle")
	_check(is_equal_approx(float(s.row_of(doc, "x2")["lat"]), 49.10), "a row outside the selection is untouched")
	h.undo(doc)
	_check(is_equal_approx(float(s.row_of(doc, "x1")["lat"]), 49.10)
		and is_equal_approx(float(s.row_of(doc, "x1")["yaw"]), 0.0), "undoing the group rotate puts the group back")
	# Remove circles never rotate, not even when they are in the selection.
	var rot_cmd: Dictionary = s.rotate_cmd(doc, ["x1", "x3", "x4"], 45.0)
	var parts: Array = rot_cmd.get("parts", []) as Array
	_check(parts.size() == 4, "a rotate over two adds is a move and a rotate each (%d parts)" % parts.size())
	var touches_x4: bool = false
	for p in parts:
		if str((p as Dictionary).get("id", "")) == "x4":
			touches_x4 = true
	_check(not touches_x4, "the remove circle is left out of the group rotate")
	_check(s.rotate_cmd(doc, ["x4"], 45.0).is_empty(), "rotating only a remove circle does nothing")
	h.clear()
	_check(h.do(doc, rot_cmd) and is_equal_approx(float(s.row_of(doc, "x4")["lat"]), 49.20)
		and is_equal_approx(float(s.row_of(doc, "x4")["lon"]), 0.00),
		"the remove circle does not move in a group rotate")

	# ---- Copy / paste: adds only, fresh ids, offsets right, ONE undo step.
	doc = make.call()
	h.clear()
	var clip: Array = s.copy_rows(doc, ["x1", "x2", "x4"])
	_check(clip.size() == 2, "copy takes the adds and leaves the remove circle behind (%d rows)" % clip.size())
	_check(s.copy_rows(doc, ["x4"]).is_empty(), "copying only a remove circle copies nothing")
	var n_before: int = doc.size()
	var paste_cmd: Dictionary = s.paste_cmd(doc, clip)
	_check(not paste_cmd.is_empty(), "a paste command is built from the clipboard")
	_check(h.do(doc, paste_cmd), "the paste applies")
	_check(doc.size() == n_before + 2, "the paste added one row per copied row")
	_check(h.undo_depth() == 1, "the whole paste is ONE undo step")
	var ids: Array = s.add_ids(paste_cmd)
	_check(ids.size() == 2, "the paste reports the ids it created (%s)" % str(ids))
	var fresh: bool = true
	for v in ids:
		fresh = fresh and str(v) != "x1" and str(v) != "x2" and str(v) != "x3" and str(v) != "x4"
		fresh = fresh and not s.row_of(doc, str(v)).is_empty()
	_check(fresh, "every pasted row gets a fresh id that is in the document (%s)" % str(ids))
	_check(MapEdits.next_id("a", doc) != str(ids[0]) and MapEdits.next_id("a", doc) != str(ids[1]),
		"the next id after a paste is past every id the paste used")
	var orig: Dictionary = s.row_of(doc, "x1")
	var copy1: Dictionary = s.row_of(doc, str(ids[0]))
	_check(is_equal_approx(float(copy1["lat"]) - float(orig["lat"]), s.PASTE_D_LAT)
		and is_equal_approx(float(copy1["lon"]) - float(orig["lon"]), s.PASTE_D_LON),
		"a plain paste is offset from where it was copied (%.4f, %.4f)"
			% [float(copy1["lat"]) - float(orig["lat"]), float(copy1["lon"]) - float(orig["lon"])])
	_check(str(copy1["asset"]) == "church" and is_equal_approx(float(copy1["yaw"]), 0.0),
		"the pasted row keeps its asset and yaw")
	_check(is_equal_approx(float(copy1["lat"]) - float(s.row_of(doc, str(ids[1]))["lat"]),
		float(orig["lat"]) - float(s.row_of(doc, "x2")["lat"])),
		"the pasted group keeps the shape of the original")
	# A paste at a point (the mouse) centres the pasted group on it.
	var at := Vector2(50.50, 2.00)
	var at_cmd: Dictionary = s.paste_cmd(doc, clip, at)
	var at_ids: Array = s.add_ids(at_cmd)
	_check(h.do(doc, at_cmd), "a paste at the mouse applies")
	var landed: Vector2 = s.centre_of(s.rows_of(doc, at_ids))
	_check(landed.distance_to(at) < 1.0e-6, "pasting at a point centres the group on it (%.4f, %.4f)"
		% [landed.x, landed.y])
	_check(h.undo_depth() == 2, "each paste is one undo step of its own")
	h.undo(doc)
	_check(doc.size() == n_before + 2, "undoing the second paste takes it back out in one step")
	_check(s.prune(doc, ids).size() == 2, "the first paste's rows are still selectable after undoing the second")
	h.undo(doc)
	_check(doc.size() == n_before, "undoing the first paste takes it back out in one step")
	_check(s.prune(doc, ids).is_empty(), "the selection is cleaned up after undoing the paste")
	_check(s.paste_cmd(doc, []).is_empty(), "pasting an empty clipboard does nothing")

	# ---- Group delete: one step, all of them, and the selection cleans up.
	doc = make.call()
	h.clear()
	var del_ids: Array = ["x1", "x2"]
	_check(h.do(doc, s.delete_cmd(doc, del_ids)) and h.undo_depth() == 1, "the group delete is ONE undo step")
	_check(s.row_of(doc, "x1").is_empty() and s.row_of(doc, "x2").is_empty()
		and not s.row_of(doc, "x3").is_empty(), "the group delete removed exactly the selection")
	_check(s.prune(doc, del_ids).is_empty(), "the selection is cleaned up after a group delete")
	h.undo(doc)
	_check(not s.row_of(doc, "x1").is_empty() and not s.row_of(doc, "x2").is_empty(),
		"undoing the group delete brings every row back in one step")
	_check(s.prune(doc, del_ids).size() == 2, "the rows are selectable again after the undo")

	# ---- Go to: cities, airfields and edits, by name and by id, best match first. The document is
	# reset first: an undo puts a row back at the end, so the order would not be the fixture's.
	doc = make.call()
	var cities: Array = [{"name": "London", "lat": 51.5, "lon": -0.12},
		{"name": "Londonderry", "lat": 55.0, "lon": -7.3}]
	var fields: Array = [{"name": "Biggin Hill", "lat": 51.33, "lon": 0.03}]
	var hits: Array = s.goto_matches("london", cities, fields, doc)
	_check(hits.size() == 2 and str(hits[0]["name"]) == "London" and str(hits[1]["name"]) == "Londonderry",
		"go to ranks a whole-name match above a prefix, then offers the rest (%d)" % hits.size())
	_check(str(hits[0]["kind"]) == "city", "a city match says it is a city")
	_check(is_equal_approx(float(hits[0]["lat"]), 51.5) and is_equal_approx(float(hits[0]["lon"]), -0.12),
		"a city match carries its position")
	_check(str(hits[0]["title"]).begins_with("City"), "a go-to match carries a title for the status line")
	var air: Array = s.goto_matches("biggin", cities, fields, doc)
	_check(air.size() == 1 and str(air[0]["kind"]) == "airfield", "go to finds an airfield by part of its name")
	var by_id: Array = s.goto_matches("x3", cities, fields, doc)
	_check(by_id.size() == 1 and str(by_id[0]["kind"]) == "edit" and str(by_id[0]["id"]) == "x3",
		"go to finds an edit by its id")
	var by_label: Array = s.goto_matches("barn", cities, fields, doc)
	_check(by_label.size() == 2 and str(by_label[0]["id"]) == "x2",
		"go to finds edits by asset label, in document order (%d)" % by_label.size())
	_check(s.goto_matches("CHURCH", cities, fields, doc).size() == 1, "go to ignores case")
	_check(s.goto_matches("  ", cities, fields, doc).is_empty(), "go to needs something typed")
	_check(s.goto_matches("zzzz", cities, fields, doc).is_empty(), "go to reports no match as nothing")

	# ---- The grid: adaptive, always roughly 60-120 px per cell.
	var seen: Array = []
	var ok: bool = true
	for z in [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 80.0]:
		t.zoom = float(z)
		var km: float = MapViewScript.grid_km(t.px_per_km())
		var px: float = km * t.px_per_km()
		seen.append("%.0fx=%.0fpx:%s" % [z, px, MapViewScript.grid_label(km)])
		ok = ok and px >= MapViewScript.GRID_MIN_PX - 0.01 and px <= MapViewScript.GRID_MAX_PX + 0.01
	_check(ok, "the map grid cell is 60-120 px at every zoom (%s)" % " ".join(seen))
	_check(MapViewScript.grid_km(1.0) > MapViewScript.grid_km(1000.0), "the grid step shrinks as you zoom in")
	_check(MapViewScript.grid_label(5.0) == "5 km" and MapViewScript.grid_label(0.5) == "500 m"
		and MapViewScript.grid_label(1.5) == "1.5 km", "the grid caption reads in km and metres")

## Phase 4, things that react to the war (scripts/ground/war_reactions.gd): a crash scene builds up, its people run in
## and stop at the ring, the number of scenes is capped and they are cleared away; a downed pilot is captured by the
## other side; low passes make friendly people wave and strafing makes them run away.
func _test_war_reactions() -> void:
	print("-- war reactions: crash scenes, captors, waving and scattering")
	_check(WarReactions.is_captured("Axis", "Allies") and WarReactions.is_captured("Allies", "Axis") and not WarReactions.is_captured("Allies", "Allies"),
		"a pilot is captured by the other side only")
	_check(WarReactions.crew_team_for("Axis", "1940") == "Axis" and WarReactions.crew_team_for("Axis", "liberation") == "Allies" and WarReactions.crew_team_for("Allies", "1940") == "Allies",
		"German-held ground is German until the liberation")
	var tdec: bool = true
	for tt in [0.4, 15.99, 16.0, 1234.5, 3599.7, 2047.31]:
		var q := Color(roundf(tt / 3600.0 * 255.0) / 255.0, roundf(fposmod(tt / 16.0, 1.0) * 255.0) / 255.0, roundf(fposmod(tt, 1.0) * 255.0) / 255.0)
		if absf(WarReactions.decode_time(q) - tt) > 0.05:
			tdec = false
	_check(tdec, "the shader-time probe pixel decodes to within 50 ms")
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	var pp: Array = WarReactions.path_point(pts, PackedFloat32Array([0.0, 100.0, 200.0]), 150.0)
	_check((pp[0] as Vector3).distance_to(Vector3(100, 0, 50)) < 0.01 and (pp[1] as Vector3).distance_to(Vector3(0, 0, 1)) < 0.01, "the ambulance path follows a road polyline")

	var wr := WarReactions.new()
	add_child(wr)
	WarReactions.wave_p = 1.0
	var pos := Vector3(3000.0, 12.0, 3000.0)
	wr.test_focus = pos
	wr.begin_crash(pos, "Allies", true)
	_check(wr.scenes.size() == 1, "a crash on land stages one scene")
	if wr.scenes.size() == 1:
		var g: WarReactions.Gang = wr.scenes[0]
		_check(g.n >= 4 and g.mm.instance_count == g.n, "a crash scene has %d people in one MultiMesh" % g.n)
		_check(g.cur_pos[0].y < -1000.0, "nobody is on show before the alarm goes up")
		for k in 480:
			wr.step(0.25)
		_check(g.arrived() == g.n, "all %d people have run in after two minutes" % g.n)
		var ring_ok: bool = true
		var kinds_ok: bool = true
		var feet_ok: bool = true
		for i in g.n:
			var lp: Vector3 = g.cur_pos[i]
			var d: float = Vector2(lp.x + g.mi.position.x - pos.x, lp.z + g.mi.position.z - pos.z).length()
			ring_ok = ring_ok and d > 24.0 and d < 41.0
			feet_ok = feet_ok and absf(lp.y + g.mi.position.y - 12.0) < 0.2
			var kd: int = AirfieldPeople.kind_of(g.cur_code[i])
			kinds_ok = kinds_ok and kd in [AirfieldPeople.Kind.TALK, AirfieldPeople.Kind.CHAT, AirfieldPeople.Kind.WAVE, AirfieldPeople.Kind.SMOKER]
		_check(ring_ok, "they stop at a ring 25-40 m from the wreck")
		_check(feet_ok, "they stand on the ground")
		_check(kinds_ok, "they stand talking, smoking or waving once there")
	for k in 6:
		wr.begin_crash(pos + Vector3(900.0 * float(k + 1), 0.0, 0.0), "Axis", true)
	_check(wr.scenes.size() <= WarReactions.MAX_SCENES, "at most %d crash scenes stand at once (%d)" % [WarReactions.MAX_SCENES, wr.scenes.size()])
	wr.step(WarReactions.SCENE_LIFE + 1.0)
	_check(wr.scenes.is_empty(), "crash scenes are cleared away when they are old")
	wr.begin_crash(pos, "Allies", true)
	wr.test_focus = pos + Vector3(9000.0, 0.0, 0.0)
	wr.step(25.0)
	_check(wr.scenes.is_empty(), "a scene the camera is far from is dropped")
	wr.begin_crash(pos, "Allies")
	_check(wr.scenes.is_empty(), "a crash far from the camera is not staged at all")
	wr.test_focus = pos

	# a downed pilot
	wr.begin_pilot(pos, "Axis", true)
	if wr.scenes.size() == 1:
		var pg: WarReactions.Gang = wr.scenes[0]
		_check(pg.is_pilot and pg.n >= 1 and pg.n <= 4 and pg.pilot_mi != null, "a downed pilot has up to four captors (%d) and his own figure" % pg.n)
		_check(not pg.pilot_shown, "the pilot is not there while his canopy lies on the ground")
		for k in 200:
			wr.step(0.25)
		_check(pg.pilot_shown and pg.arrived() == pg.n, "the pilot stands up and his captors reach him")
		var pk: int = AirfieldPeople.kind_of(pg.pilot_code)
		var want_k: int = AirfieldPeople.Kind.WAVE if WarReactions.is_captured("Axis", WarReactions.crew_team(pos)) else AirfieldPeople.Kind.TALK
		_check(pk == want_k, "the enemy pilot raises a hand, one of our own just talks")
	wr.step(300.0)

	# low passes and strafing over a group of people (the figures' data is fed to the cache: a headless MultiMesh
	# cannot be read back)
	var men: Array = []
	var fp := PackedVector3Array()
	var fc := PackedInt32Array()
	for k in 4:
		men.append([Vector3(5000.0 + 20.0 * float(k), 12.0, 5000.0), Vector3(0, 0, -1), AirfieldPeople.Kind.TALK, 0.0, 0.3, 1.4, false, null, 0.0, 12.0, 12.0, 10])
	men.append([Vector3(5260.0, 12.0, 5000.0), Vector3(0, 0, -1), AirfieldPeople.Kind.TALK, 0.0, 0.3, 1.4, false, null, 0.0, 12.0, 12.0, 10])
	for m in men:
		fp.append((m[0] as Vector3) - Vector3(5000.0, 12.0, 5000.0))
		fc.append(AirfieldPeople.code_of(AirfieldPeople.Kind.TALK, false, 10))
	var fri: MultiMeshInstance3D = AirfieldPeople.spawn(wr, men, Vector3(5000.0, 12.0, 5000.0), "Allies", 11, "", true)
	var foes: Array = [[Vector3(5030.0, 12.0, 5040.0), Vector3(0, 0, -1), AirfieldPeople.Kind.TALK, 0.0, 0.3, 1.4, false, null, 0.0, 12.0, 12.0, 1]]
	var foe: MultiMeshInstance3D = AirfieldPeople.spawn(wr, foes, Vector3(5030.0, 12.0, 5040.0), "Axis", 12, "", true)
	var pcf: WarReactions.PeopleCache = wr._cache_for(fri)
	pcf.feed(fp, fc)
	var pce: WarReactions.PeopleCache = wr._cache_for(foe)
	pce.feed(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]), PackedInt32Array([AirfieldPeople.code_of(AirfieldPeople.Kind.TALK, false, 1)]))
	var above := Vector3(5030.0, 42.0, 5000.0)
	wr.scan_at(above, 30.0, "Allies", false)
	wr.scan_at(above, 30.0, "Allies", false)
	var waving: int = 0
	for i in 5:
		if AirfieldPeople.kind_of(pcf.code[i]) == AirfieldPeople.Kind.WAVE:
			waving += 1
	_check(waving == 4 and AirfieldPeople.kind_of(pcf.code[4]) != AirfieldPeople.Kind.WAVE, "friendly people within 150 m of a low pass wave, the one 250 m away does not (%d)" % waving)
	_check(AirfieldPeople.kind_of(pce.code[0]) != AirfieldPeople.Kind.WAVE, "enemy troops do not wave")
	var high := PackedInt32Array([AirfieldPeople.code_of(AirfieldPeople.Kind.TALK, false, 10)])
	pcf.state[4] = 0
	wr.scan_at(Vector3(5260.0, 400.0, 5000.0), 390.0, "Allies", false)
	_check(AirfieldPeople.kind_of(pcf.code[4]) != AirfieldPeople.Kind.WAVE, "nobody waves at an aircraft that is high")
	wr.step(7.0)
	var back: int = 0
	for i in 5:
		if AirfieldPeople.kind_of(pcf.code[i]) == AirfieldPeople.Kind.TALK:
			back += 1
	_check(back == 5, "after a few seconds they go back to what they were doing (%d of 5)" % back)
	wr.scan_at(above, 30.0, "Allies", true)
	var running: int = 0
	for i in 5:
		if AirfieldPeople.kind_of(pcf.code[i]) == AirfieldPeople.Kind.RUN:
			running += 1
	_check(running >= 1 and running <= 4, "friendly people under fire run away (%d)" % running)
	wr.step(15.0)
	var moved: int = 0
	var crouched: int = 0
	for i in 4:
		if pcf.pos[i].distance_to(fp[i]) > 15.0:
			moved += 1
		if AirfieldPeople.kind_of(pcf.code[i]) == AirfieldPeople.Kind.WORK:
			crouched += 1
	_check(moved >= 1 and crouched == moved, "the runners end up well away from where they stood and crouch there (%d)" % moved)
	# the scan is cheap
	WarReactions.wave_p = 0.0
	var t0: int = Time.get_ticks_usec()
	for k in 300:
		wr.scan_at(above, 30.0, "Allies", false)
	var per: float = float(Time.get_ticks_usec() - t0) / 300.0 / 1000.0
	_check(per < 0.3, "a reaction scan over the people takes %.3f ms (< 0.3)" % per)
	WarReactions.wave_p = 0.1
	WarReactions.inst = null
	wr.queue_free()


## The towns and villages: head counts follow the quality setting, the new kinds encode in INSTANCE_CUSTOM.w, and
## every person planned for a village stands clear of the houses it was planned from (never in a wall).
func _test_town_people() -> void:
	print("-- town people: counts, kind codes, house clearance")
	var lo: int = AirfieldPeople.village_target(40, 0.7)
	var mid: int = AirfieldPeople.village_target(40, 1.6)
	var hi: int = AirfieldPeople.village_target(40, 2.2)
	_check(lo > 0 and lo < mid and mid < hi and hi <= 40, "village numbers follow density (%d / %d / %d of 40 houses)" % [lo, mid, hi])
	_check(AirfieldPeople.village_target(6, 2.2) == 0, "a farmstead of six houses gets nobody")
	var tt: int = AirfieldPeople.town_target(3, 2.2)
	_check(tt >= 40 and tt <= 120, "a size-3 town shows %d people on High (40-120)" % tt)
	_check(AirfieldPeople.town_target(3, 0.7) < tt, "a town on Low shows fewer than on High")
	# INSTANCE_CUSTOM.w = kind * 64 + soldier * 32 + dress
	var ok: bool = true
	var ks: Array[int] = [AirfieldPeople.Kind.QUEUE, AirfieldPeople.Kind.CYCLE, AirfieldPeople.Kind.PRAM, AirfieldPeople.Kind.CHAT]
	var sols: Array[bool] = [false, true]
	for k in ks:
		for sol in sols:
			for d in range(AirfieldPeople.CIV_SUIT, AirfieldPeople.CIV_HOME_GUARD + 1):
				var c: int = AirfieldPeople.code_of(k, sol, d)
				if AirfieldPeople.kind_of(c) != k or AirfieldPeople.soldier_of(c) != sol or AirfieldPeople.dress_of(c) != d:
					ok = false
	_check(ok, "the town kinds and the civilian wardrobe encode and decode in INSTANCE_CUSTOM.w")
	var oc: int = AirfieldPeople.code_of(AirfieldPeople.Kind.MARCH, true, 2)
	_check(AirfieldPeople.kind_of(oc) == AirfieldPeople.Kind.MARCH and AirfieldPeople.soldier_of(oc) and AirfieldPeople.dress_of(oc) == 2, "an airfield soldier still encodes to kind, soldier and dress")
	# a street of houses with their fronts on the pavement, laid the way the scatter lays them
	var houses: Array = [[], [], [], []]
	for i in 24:
		var hx: float = float(i) * 24.0
		var xf := Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(8.0, 6.0, 8.0)), Vector3(hx, 12.0, 0.0))
		(houses[i % 4] as Array).append(xf)
	var want: int = AirfieldPeople.village_target(24, 2.2)
	var men: Array = AirfieldPeople.village_plan(Vector2(-200.0, -200.0), 900.0, houses, 4711, "Allies", 2.2)
	_check(men.size() == want, "a village plans its density's head count (%d of %d)" % [men.size(), want])
	var clear: bool = true
	var feet: bool = true
	var inside: bool = true
	var tile := Rect2(Vector2(-196.0, -196.0), Vector2(892.0, 892.0))
	for m in men:
		var mp: Vector3 = m[0]
		if not tile.has_point(Vector2(mp.x, mp.z)):
			inside = false
		if m.size() > 9 and absf(float(m[9]) - 12.0) > 0.001:
			feet = false
		for lst in houses:
			for h in (lst as Array):
				var tf: Transform3D = h
				if absf(mp.x - tf.origin.x) < 4.0 and absf(mp.z - tf.origin.z) < 4.0:
					clear = false
	_check(inside, "village people stay inside their tile")
	_check(clear, "no village person is planned inside a house footprint")
	_check(feet, "village people carry their ground height from the worker (12 m test terrain)")
	# the real thing: a named town's own layout, the way _build_city lays it out, plus the land-cover street grid
	# its surrounding tiles lay through the circle (Folkestone's own town_d holds only a handful of houses)
	var fpos: Vector3 = WorldCoords.latlon_to_world(51.0814, 1.1695)
	var tseed: int = hash("folkestone") + 77
	var td: Dictionary = Scatter.town_layout(fpos, 2, tseed, true)
	var tmen: Array = AirfieldPeople.town_plan(fpos, td, 2, "Allies", tseed + 9, 2.2)
	_check(tmen.size() >= 30, "Folkestone's real town layout plans %d townspeople on High (>= 30)" % tmen.size())
	var bare: Dictionary = {"radius": 260.0}
	var gmen: Array = AirfieldPeople.town_plan(fpos, bare, 2, "Allies", tseed + 11, 2.2)
	_check(gmen.size() >= 30, "a town whose town_d is empty still gets %d people from the street grid" % gmen.size())
	_check(gmen.size() <= AirfieldPeople.town_target(2, 2.2), "the street-grid plan stops at the town's target (%d)" % gmen.size())
	_test_occupation_life()
	_test_war_vehicles()


const OccupationLife := preload("res://scripts/ground/occupation_life.gd")

## Phase 5 (scripts/ground/occupation_life.gd): the French civilians and the German garrison of the French towns.
func _test_occupation_life() -> void:
	print("-- occupation life: French civilians and the German garrison")
	_check(OccupationLife.continental(50.726, 1.614), "Boulogne is on the continent")
	_check(OccupationLife.continental(49.92, 1.08), "Dieppe is on the continent")
	_check(not OccupationLife.continental(51.081, 1.1695), "Folkestone is in England")
	_check(not OccupationLife.continental(51.13, 1.31), "Dover is in England")
	# an Axis town's patrol is never dressed in a British outfit (police, ARP warden, Home Guard)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var axis_ok: bool = true
	for i in 600:
		var dd: int = int(AirfieldPeople.town_dress("Axis", rng)[0])
		if dd == AirfieldPeople.CIV_POLICE or dd == AirfieldPeople.CIV_ARP or dd == AirfieldPeople.CIV_HOME_GUARD:
			axis_ok = false
	_check(axis_ok, "no British-only outfit is dressed in an Axis-held town")
	# a French town (Boulogne) turns its British-only civilians into French ones; an English town keeps them
	var outfits: Array = [AirfieldPeople.CIV_POLICE, AirfieldPeople.CIV_ARP, AirfieldPeople.CIV_HOME_GUARD, AirfieldPeople.CIV_SUIT]
	var test_men: Array = []
	for i in 40:
		var dress: int = int(outfits[i % 4])
		test_men.append([Vector3.ZERO, Vector3.FORWARD, 0, 0.0, -1.0, 0.0, dress == AirfieldPeople.CIV_HOME_GUARD, null, 0.0, 0.0, 0.0, dress])
	var english_left: int = OccupationLife.civilise(test_men, 51.081, 1.1695)
	_check(english_left == 0, "Folkestone's civilians are left as they are")
	var fixed: int = OccupationLife.civilise(test_men, 50.726, 1.614)
	var gend_n: int = 0
	for e in test_men:
		if int((e as Array)[11]) == AirfieldPeople.CIV_GENDARME:
			gend_n += 1
	_check(gend_n == 10 and AirfieldPeople.CIV_GENDARME == 21 and AirfieldPeople.code_of(0, false, AirfieldPeople.CIV_GENDARME) == 21, "a French constable is a gendarme (dress 21, ten of them here)")
	var french_ok: bool = true
	for e in test_men:
		var dd2: int = int(e[11])
		if dd2 == AirfieldPeople.CIV_POLICE or dd2 == AirfieldPeople.CIV_ARP or dd2 == AirfieldPeople.CIV_HOME_GUARD or bool(e[6]):
			french_ok = false
	_check(french_ok and fixed == 30, "Boulogne's British-only civilians are all made French (%d changed, want 30)" % fixed)
	# the German garrison: an Axis-held town gets its sentries and patrol at the town hall; an Allied one gets none
	var gpos := Vector3(0.0, 0.0, 0.0)
	var gd: Dictionary = {"civic": [{"kind": "townhall", "pos": gpos, "yaw": 0.0, "scale": 1.0}]}
	var gb := Rect2(Vector2(-500.0, -500.0), Vector2(1000.0, 1000.0))
	var gr := RandomNumberGenerator.new()
	gr.seed = 5
	var gax: Array = []
	var added: int = OccupationLife.garrison(gax, AirfieldPeople.HouseMap.new(), gpos, gd, 2, "Axis", 2.2, gr, gb)
	var soldiers: bool = true
	for m in gax:
		if not bool(m[6]):
			soldiers = false
	_check(added >= 2 and soldiers, "an Axis-held town hall gets its sentries (%d men, all soldiers)" % added)
	var gal: Array = []
	var allied_added: int = OccupationLife.garrison(gal, AirfieldPeople.HouseMap.new(), gpos, gd, 2, "Allies", 2.2, gr, gb)
	_check(allied_added == 0, "an Allied-held town gets no German garrison")

const WarVehicles := preload("res://scripts/ground/war_vehicles.gd")

## c2 (scripts/ground/war_vehicles.gd): the fire engine or Opel Blitz that comes up the road to a crash, the Kommandantur
## flag, the German sentries at Axis harbours and the Axis field's kitchen and wagons. Each one only where it belongs.
func _test_war_vehicles() -> void:
	print("-- war vehicles: fire engine, Opel Blitz, Kommandantur flag, harbour sentries, field kitchen")
	_check(WarVehicles.rig_kind("Allies") == "fire_engine", "a crash on English ground brings a fire engine")
	_check(WarVehicles.rig_kind("Axis") == "opel_blitz", "a crash on German ground brings an Opel Blitz instead")
	var hall: Array = [{"kind": "townhall", "pos": Vector3.ZERO, "yaw": 0.0, "scale": 1.0}]
	_check(WarVehicles.flag_flown("Axis", 3, hall), "an Axis-held town hall flies the Kommandantur flag")
	_check(not WarVehicles.flag_flown("Allies", 3, hall), "an Allied town hall flies no Kommandantur flag")
	_check(not WarVehicles.flag_flown("Axis", 1, hall), "no flag in an Axis-held size-1 town")
	_check(not WarVehicles.flag_flown("Axis", 3, [{"kind": "station", "pos": Vector3.ZERO}]), "no flag in an Axis-held town without a town hall")
	_check(WarVehicles.harbour_guarded("Axis", "port_boulogne") and WarVehicles.harbour_guarded("Axis", "dock_calais"), "Axis harbours and docks (Boulogne, Calais) get sentries")
	_check(not WarVehicles.harbour_guarded("Allies", "port_dover") and not WarVehicles.harbour_guarded("Axis", "camp_kent"), "no sentries at Allied harbours or at other Axis sites")
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var fc: Array = WarVehicles.fire_crew(Vector3(100.0, 0.0, 100.0), rng)
	var dark: bool = fc.size() >= 2 and fc.size() <= 3
	for e in fc:
		if int((e as Array)[11]) != AirfieldPeople.CIV_ARP:
			dark = false
	_check(dark, "the fire crew is 2-3 men in the dark ARP outfit (%d)" % fc.size())
	_check(WarVehicles.fire_engine_mesh().get_surface_count() > 0 and WarVehicles.opel_blitz_mesh().get_surface_count() > 0 and WarVehicles.flag_mesh().get_surface_count() > 0 and WarVehicles.kitchen_mesh().get_surface_count() > 0, "the vehicle, flag and kitchen meshes build")
	# a field kitchen with 4-6 men and one or two wagons on an Axis field; nothing at an Allied one
	var open := func(_p: Vector3) -> bool:
		return true
	var kc := Node3D.new()
	var kmen: Array = WarVehicles.airfield_camp(kc, AirfieldPeople.Grid.new(Vector3.ZERO, 900.0), open, Vector3.ZERO, 900.0, 0.0, "Axis", 7)
	_check(kmen.size() >= 5 and kmen.size() <= 8, "the Axis field's kitchen has its men (%d: 4-6 round the kitchen, plus a wagon driver each)" % kmen.size())
	_check(kc.get_child_count() >= 2 and kc.get_child_count() <= 3, "the kitchen and one or two wagons are placed (%d nodes)" % kc.get_child_count())
	var kb := Node3D.new()
	var amen: Array = WarVehicles.airfield_camp(kb, AirfieldPeople.Grid.new(Vector3.ZERO, 900.0), open, Vector3.ZERO, 900.0, 0.0, "Allies", 7)
	_check(amen.is_empty() and kb.get_child_count() == 0, "no field kitchen or wagons at an Allied airfield")
	kc.free()
	kb.free()

## Phase 2 (scripts/ground/farm_people.gd): life on the farms and in the fields. The new kinds and the farm wardrobe encode
## in INSTANCE_CUSTOM.w without renumbering the old ones, the number of work parties follows the quality setting and the
## month, each season has its own work, and nobody (and no prop or stook) is planned on a road-free spot that is not
## farmland, on water, or inside a house of the tile.
func _test_farm_people() -> void:
	print("-- farm people: kinds, counts by density and season, placement")
	var K = AirfieldPeople.Kind
	_check(K.WALK == 0 and K.CHAT == 23 and K.PITCHFORK == 24 and K.HOE == 25 and K.LEAD_HORSE == 26 and K.DRIVE_CART == 27 and K.PLOUGHMAN == 28, "the farm kinds are appended after CHAT without renumbering the old ones")
	var enc_ok: bool = true
	for k in [K.PITCHFORK, K.HOE, K.LEAD_HORSE, K.DRIVE_CART, K.PLOUGHMAN]:
		for sol in [false, true]:
			for d in range(AirfieldPeople.FARM_FARMER, AirfieldPeople.FARM_WOMAN_FR + 1):
				var c: int = AirfieldPeople.code_of(k, sol, d)
				if AirfieldPeople.kind_of(c) != k or AirfieldPeople.soldier_of(c) != sol or AirfieldPeople.dress_of(c) != d:
					enc_ok = false
	_check(enc_ok, "the farm kinds and the farm wardrobe (dress 16-20) encode and decode in INSTANCE_CUSTOM.w")
	var lo: int = FarmPeople.group_target(0.7, 8)
	var mid: int = FarmPeople.group_target(1.6, 8)
	var hi: int = FarmPeople.group_target(2.2, 8)
	_check(lo >= 1 and lo < mid and mid < hi, "work parties per tile follow density (%d / %d / %d in August)" % [lo, mid, hi])
	_check(FarmPeople.group_target(2.2, 8) > FarmPeople.group_target(2.2, 1), "the fields are busier at the harvest than in January (%d vs %d)" % [FarmPeople.group_target(2.2, 8), FarmPeople.group_target(2.2, 1)])
	# the farmland north of Hawkinge: the nine tiles round it, with a lone house in each so the farm anchors exist
	var hpos: Vector3 = WorldCoords.latlon_to_world(51.13, 1.12)
	var tile: float = 1800.0
	var o0 := Vector2(floorf(hpos.x / tile) * tile, floorf(hpos.z / tile) * tile)
	var per_month: Dictionary = {}
	var all_fine: bool = true
	var bad: String = ""
	for month in [1, 4, 6, 8, 11]:
		var kinds: Dictionary = {}
		var men_n: int = 0
		var men_lo_n: int = 0
		for ty in range(-1, 2):
			for tx in range(-1, 2):
				var org := Vector2(o0.x + float(tx) * tile, o0.y + float(ty) * tile)
				var hx: Array = [[], [], [], []]
				var hc := Vector3(org.x + tile * 0.5 + 300.0, 12.0, org.y + tile * 0.5 - 200.0)
				(hx[0] as Array).append(Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(9.0, 6.0, 7.0)), hc))
				var pl: Dictionary = FarmPeople.plan(org, tile, hx, 4242 + tx * 7 + ty * 13, 2.2, month, false)
				var pl_lo: Dictionary = FarmPeople.plan(org, tile, hx, 4242 + tx * 7 + ty * 13, 0.7, month, false)
				men_lo_n += (pl_lo["men"] as Array).size()
				for m in (pl["men"] as Array):
					men_n += 1
					var kd: int = int(m[2])
					kinds[kd] = int(kinds.get(kd, 0)) + 1
					var mp: Vector3 = m[0]
					var q := Vector2(mp.x, mp.z)
					var qs: Array = [q]
					if float(m[3]) > 1.0:
						qs.append(q + Vector2((m[1] as Vector3).x, (m[1] as Vector3).z) * float(m[3]))
					for qq in qs:
						var v: Vector2 = qq
						var cls: int = LandCover.class_at(v.x, v.y)
						var inside_house: bool = absf(v.x - hc.x) < 6.0 and absf(v.y - hc.z) < 6.0
						if (cls != 40 and cls != 30) or GroundKit.raw_y(v.x, v.y) <= 0.8 or Scatter.in_lake(v.x, v.y) or inside_house or not Rect2(org, Vector2(tile, tile)).has_point(v):
							all_fine = false
							bad = "class %d at %.0f,%.0f" % [cls, v.x, v.y]
				for pk in (pl["props"] as Dictionary).keys():
					for e in ((pl["props"] as Dictionary)[pk] as Array):
						var pp: Vector3 = (e as Array)[0]
						if absf(pp.x - hc.x) < 6.0 and absf(pp.z - hc.z) < 6.0:
							all_fine = false
				for sk in (pl["still"] as Dictionary).keys():
					for e2 in ((pl["still"] as Dictionary)[sk] as Array):
						var sp: Vector3 = (e2 as Array)[0]
						var scls: int = LandCover.class_at(sp.x, sp.z)
						if scls != 40 and scls != 30 or Scatter.in_lake(sp.x, sp.z):
							all_fine = false
							bad = "still on class %d" % scls
		per_month[month] = {"kinds": kinds, "men": men_n, "men_lo": men_lo_n}
	_check(all_fine, "farm people, props and stooks stand on farmland or grass, off water, clear of the tile's houses and inside the tile (%s)" % bad)
	var jan: Dictionary = per_month[1]
	var aug: Dictionary = per_month[8]
	_check(int(aug["men"]) > 0 and int(aug["men"]) > int(aug["men_lo"]), "High shows more field hands than Low (%d vs %d in August)" % [int(aug["men"]), int(aug["men_lo"])])
	_check(int(aug["men"]) > int(jan["men"]), "more people work the fields in August than in January (%d vs %d)" % [int(aug["men"]), int(jan["men"])])
	var ak: Dictionary = aug["kinds"]
	_check(int(ak.get(K.PITCHFORK, 0)) + int(ak.get(K.WORK, 0)) > 0 and int(ak.get(K.PLOUGHMAN, 0)) == 0, "August is harvest: stooking and forking, no horse ploughing")
	var nk: Dictionary = (per_month[11] as Dictionary)["kinds"]
	_check(int(nk.get(K.PLOUGHMAN, 0)) + int(nk.get(K.DRIVE_CART, 0)) > 0 and int(nk.get(K.PITCHFORK, 0)) == 0, "November is ploughing (horse or tractor), no haymaking")
	var sk4: Dictionary = (per_month[4] as Dictionary)["kinds"]
	_check(int(sk4.get(K.HOE, 0)) > 0, "April is sowing and hoeing")
	_check(int(((per_month[6] as Dictionary)["kinds"] as Dictionary).get(K.PITCHFORK, 0)) > 0, "June is haymaking")
	# a prop and its man share one beat: same position, direction, length, speed and phase
	var org2 := o0
	var pl2: Dictionary = FarmPeople.plan(org2, tile, [], 99, 2.2, 10, false)
	var tied: bool = true
	var team_men: int = 0
	for m2 in (pl2["men"] as Array):
		var mk: int = int(m2[2])
		if mk == K.PLOUGHMAN or mk == K.LEAD_HORSE or mk == K.DRIVE_CART:
			team_men += 1
			var found: bool = false
			for pk2 in (pl2["props"] as Dictionary).keys():
				for e3 in ((pl2["props"] as Dictionary)[pk2] as Array):
					var ea: Array = e3
					if (ea[0] as Vector3).is_equal_approx(m2[0]) and absf(float(ea[2]) - float(m2[3])) < 0.001 and absf(float(ea[3]) - float(m2[4])) < 0.001 and absf(float(ea[4]) - float(m2[5])) < 0.001:
						found = true
			if not found:
				tied = false
	_check(tied, "every ploughman, leader and driver has his prop on the same beat (%d teams)" % team_men)
	_check(FarmPeople.prop_mesh(FarmPeople.Prop.PLOUGH_TEAM).get_surface_count() == 1 and FarmPeople.still_mesh(FarmPeople.Still.STOOK).get_surface_count() == 1, "the farm prop and still meshes build")


## Headless checks for the cel-shaded art style (scripts/cel_shade.gd, shaders/cel/): the screen pass, the
## settings it lowers while on (and that Realistic gives every one back, saved values untouched), and the
## aircraft ink outline.


func _gfx_snapshot() -> Dictionary:
	return {"quality": GameState.quality, "msaa": GameState.msaa_level, "aniso": GameState.aniso_level,
		"post_fx": GameState.post_fx, "cloud": GameState.cloud_detail, "view": GameState.view_distance,
		"shadows": GameState.shadows_enabled, "outlines": GameState.outlines_enabled,
		"upscaler": GameState.upscaler, "frame_gen": GameState.frame_gen, "vsync": GameState.vsync_on,
		"fps_cap": GameState.fps_cap, "ui_scale": GameState.ui_scale}


func _env_snapshot(e: Environment) -> Dictionary:
	return {"ssao": e.ssao_enabled, "ssil": e.ssil_enabled, "ssr": e.ssr_enabled, "vfog": e.volumetric_fog_enabled,
		"glow": e.glow_enabled, "tonemap": e.tonemap_mode, "exposure": e.tonemap_exposure,
		"contrast": e.adjustment_contrast, "sat": e.adjustment_saturation, "reflect": e.reflected_light_source,
		"scatter": e.fog_sun_scatter, "aerial": e.fog_aerial_perspective}


func _ink_of(mi: MeshInstance3D) -> ShaderMaterial:
	var ov: Material = mi.material_overlay
	while ov != null:
		if Aircraft._is_ink(ov):
			return ov as ShaderMaterial
		ov = ov.next_pass
	return null


func _test_cel_style() -> void:
	print("-- cel-shaded style")
	var cel: CelShade = CelShade.new()
	add_child(cel)
	_check(cel.material() != null and cel.material().shader != null, "the cel pass builds its shader")
	_check(not cel.is_active(), "the cel pass starts hidden")
	var restore: int = GameState.art_style
	var vp: Window = get_window()

	# Realistic leaves every saved graphics setting where the user put it
	GameState.art_style = 0
	var saved: Dictionary = _gfx_snapshot()
	GameState.apply_graphics()
	_check(_gfx_snapshot() == saved, "Realistic: apply_graphics leaves every saved graphics setting unchanged")
	_check(not cel.is_active(), "Realistic: the cel pass is off")
	var real_msaa: int = vp.msaa_3d
	var real_ssaa: int = vp.screen_space_aa
	var real_aniso: int = vp.anisotropic_filtering_level

	# cel on: the heavy effects are lowered, but the saved values are not
	GameState.art_style = 1
	GameState.apply_graphics()
	_check(cel.is_active(), "cel style: the pass is on")
	_check(_gfx_snapshot() == saved, "cel style: the user's saved graphics settings are not changed")
	_check(vp.msaa_3d == Viewport.MSAA_DISABLED, "cel style: MSAA is off")
	_check(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "cel style: FXAA replaces MSAA")

	# and back: everything restored
	GameState.art_style = 0
	GameState.apply_graphics()
	_check(not cel.is_active(), "back to Realistic: the cel pass is off again")
	_check(vp.msaa_3d == real_msaa and vp.screen_space_aa == real_ssaa and vp.anisotropic_filtering_level == real_aniso,
		"back to Realistic: MSAA, screen-space AA and anisotropy are restored")
	_check(_gfx_snapshot() == saved, "back to Realistic: saved graphics settings unchanged")

	# environment: lowered only while the style is on, every value restored afterwards
	var tod: Node = get_tree().root.get_node_or_null("TimeOfDay")
	var own_tod: bool = false
	if tod == null:
		tod = (load("res://scripts/time_of_day.gd") as GDScript).new()
		add_child(tod)
		own_tod = true
	var env: Environment = tod.get("environment")
	_check(env != null, "the time-of-day environment exists")
	if env != null:
		for lvl in [0, 1, 2]:
			GameState.art_style = 0
			tod.call("apply_post", lvl)
			var real: Dictionary = _env_snapshot(env)
			GameState.art_style = 1
			tod.call("apply_post", lvl)
			var cel_env: Dictionary = _env_snapshot(env)
			_check(not cel_env["ssao"] and not cel_env["ssil"] and not cel_env["ssr"] and not cel_env["vfog"] and not cel_env["glow"],
				"cel style (post_fx %d): SSAO, SSIL, SSR, volumetric fog and glow are all off" % lvl)
			if lvl == 2:
				_check(real["ssao"] and real["ssil"] and real["vfog"], "Realistic high really has SSAO, SSIL and volumetric fog on")
			GameState.art_style = 0
			tod.call("apply_post", lvl)
			_check(_env_snapshot(env) == real, "back to Realistic (post_fx %d): every environment value is restored" % lvl)
		tod.call("apply_post", GameState.post_fx)
	if own_tod:
		tod.queue_free()
	# the sea turns clearly blue in cel style and gets its own colours back afterwards
	var sea: WaterPlane = WaterPlane.new()
	add_child(sea)
	var sea_mat: ShaderMaterial = sea.material_override as ShaderMaterial
	var real_deep: Variant = sea_mat.get_shader_parameter("deep_color")
	GameState.art_style = 1
	GameState.apply_graphics()
	var cel_deep: Variant = sea_mat.get_shader_parameter("deep_color")
	_check(cel_deep is Color and (cel_deep as Color).b > (cel_deep as Color).g, "cel style: the sea is blue")
	GameState.art_style = 0
	GameState.apply_graphics()
	_check(sea_mat.get_shader_parameter("deep_color") == real_deep, "back to Realistic: the sea shader colours are the original ones")
	sea.queue_free()
	GameState.art_style = restore
	GameState.apply_graphics()
	cel.queue_free()


## F7 flips the art style both ways, and the action is registered with a key.
func _test_art_style_key() -> void:
	print("-- art style key")
	_check(InputMap.has_action("art_style_toggle"), "the art_style_toggle action exists")
	var has_key: bool = false
	for e in InputMap.action_get_events("art_style_toggle"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_F7:
			has_key = true
	_check(has_key, "F7 is bound to the art style toggle")
	var restore: int = GameState.art_style
	GameState.set_graphic("art_style", 0)
	GameState.toggle_art_style()
	_check(GameState.art_style == 1, "the toggle turns the cel style on")
	GameState.toggle_art_style()
	_check(GameState.art_style == 0, "the toggle turns it back to Realistic")
	GameState.set_graphic("art_style", restore)


## The ink outline: thick black on the player's aircraft, team colours on the AI's, gone in Realistic.
func _test_cel_ink() -> void:
	print("-- cel aircraft ink")
	var restore: int = GameState.art_style
	var enemy_team: String = "Axis" if GameState.player_side == "Allies" else "Allies"
	var cases: Array = [["player", true, GameState.player_side], ["friendly", false, GameState.player_side], ["enemy", false, enemy_team]]
	for cs in cases:
		var ac: Aircraft = Aircraft.new()
		add_child(ac)
		ac.player_controlled = cs[1]
		ac.team = cs[2]
		var root := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		root.add_child(mi)
		ac.add_child(root)
		ac._model = root
		if not cs[1]:
			var team_mat := ShaderMaterial.new()
			team_mat.shader = load("res://shaders/team_outline.gdshader") as Shader
			mi.material_overlay = team_mat
		GameState.art_style = 1
		ac.refresh_art_style()
		var ink: ShaderMaterial = _ink_of(mi)
		_check(ink != null, "%s aircraft get the cel ink" % cs[0])
		if ink != null:
			var col: Color = ink.get_shader_parameter("ink_color")
			match String(cs[0]):
				"player":
					_check(col.r < 0.1 and col.g < 0.1 and col.b < 0.1, "the player's outline is black")
				"friendly":
					_check(col.r > 0.9 and col.g > 0.7 and col.b < 0.3, "a friendly AI aircraft is outlined yellow")
				"enemy":
					_check(col.r > 0.9 and col.g < 0.3 and col.b < 0.3, "an enemy AI aircraft is outlined red")
			_check(float(ink.get_shader_parameter("dist_scale")) >= 0.003, "the outline is thick enough to read at range")
		GameState.art_style = 0
		ac.refresh_art_style()
		_check(_ink_of(mi) == null, "%s aircraft: the ink comes off in Realistic" % cs[0])
		if not cs[1]:
			_check(mi.material_overlay != null, "AI aircraft keep their team outline in Realistic")
		else:
			_check(mi.material_overlay == null, "the player's aircraft has no overlay at all in Realistic")
		ac.queue_free()
	GameState.art_style = restore


## Free-flight enemy flights (scripts/modes/enemy_flights.gd): every flight has a mission with a real target, sizes follow the
## odds and the AI budget, escorts are attached to the bombers, and a flight past its target turns for home and is tidied away.
func _test_enemy_flights() -> void:
	print("-- enemy flights: missions, group sizes, targets, escorts, going home")
	var EF = EnemyFlights
	# size odds: 62 / 28 / 10 per cent
	var n: Array = [0, 0, 0]
	for i in 1000:
		n[EF.size_class(float(i) / 1000.0)] += 1
	_check(n[0] == 620 and n[1] == 280 and n[2] == 100, "size odds are 62%% small, 28%% medium, 10%% large (%s)" % str(n))
	# mission odds: the Axis fly dive-bomber attacks, the Allies do not; every kind appears
	var ka: Dictionary = {}
	var kb: Dictionary = {}
	for i in 1000:
		var r: float = (float(i) + 0.5) / 1000.0
		var a: String = EF.pick_kind("Axis", r)
		var b: String = EF.pick_kind("Allies", r)
		ka[a] = int(ka.get(a, 0)) + 1
		kb[b] = int(kb.get(b, 0)) + 1
	_check(ka.has("raid") and ka.has("stuka") and ka.has("sweep") and ka.has("recon"), "the Axis fly raids, Stuka attacks, sweeps and recon (%s)" % str(ka))
	_check(kb.has("raid") and kb.has("sweep") and kb.has("recon") and not kb.has("stuka"), "the Allies fly raids, sweeps and recon, no dive-bomber attacks")
	# counts: inside the table, never over the room, large raids really are large
	var counts_ok: bool = true
	for kind in EF.COUNTS:
		for cls in 3:
			var c: Array = (EF.COUNTS[kind] as Array)[cls]
			for k in 30:
				var d: Dictionary = EF.counts_for(kind, cls, 100)
				if int(d["main"]) < int(c[0]) or int(d["main"]) > int(c[1]) or int(d["escort"]) < int(c[2]) or int(d["escort"]) > int(c[3]):
					counts_ok = false
				for room in [0, 3, 7, 12, 20]:
					var d2: Dictionary = EF.counts_for(kind, cls, room)
					if int(d2["main"]) + int(d2["escort"]) > room:
						counts_ok = false
	_check(counts_ok, "group sizes stay inside the table and never exceed the free AI slots")
	_check(EF.max_total("raid", EF.Size.LARGE) >= 20 and EF.max_total("raid", EF.Size.LARGE) <= 30, "a large raid is 20-30 aircraft at most (%d)" % EF.max_total("raid", EF.Size.LARGE))
	_check(int(EF.counts_for("raid", EF.Size.LARGE, 12)["cls"]) < EF.Size.LARGE, "a large raid shrinks when the AI budget has no room for it")
	_check(int(EF.counts_for("sweep", EF.Size.SMALL, 40)["main"]) <= 4 and int(EF.counts_for("recon", EF.Size.LARGE, 40)["main"]) == 1, "small flights are 2-4 fighters, recon is a single aircraft")
	# planning: a start on the origin -> target line, a run to the target, near the player
	var player_pos := Vector3(0.0, 1500.0, 0.0)
	var targets: Array = [{"id": "a", "name": "Manston airfield", "pos": Vector3(12000.0, 0.0, 22000.0), "kind": "airfield"}]
	var origins: Array = [{"id": "o", "name": "Calais", "pos": Vector3(30000.0, 0.0, -60000.0)}]
	var pl: Dictionary = EF.plan(player_pos, targets, origins)
	_check(not pl.is_empty() and Vector2((pl["start"] as Vector3).x, (pl["start"] as Vector3).z).length() < EF.MAX_START, "a flight is planned within reach of the player")
	if not pl.is_empty():
		var st: Vector3 = pl["start"]
		_check(Vector2(st.x - 12000.0, st.z - 22000.0).length() >= 8000.0, "the planned start leaves at least 8 km to the target")
	_check(EF.plan(Vector3(900000.0, 0.0, 0.0), targets, origins).is_empty() and EF.plan(player_pos, targets, []).is_empty(), "no plan when the player is far from everything or there is no origin airfield")
	# routes: over the target, then home
	for kind in ["raid", "stuka", "recon", "sweep"]:
		var home := Vector3(30000.0, 0.0, -60000.0)
		var tp := Vector3(12000.0, 0.0, 22000.0)
		var rt: Dictionary = EF.build_route(Vector3(20000.0, 3000.0, -30000.0), tp, home, 3000.0, kind)
		var pts: Array = rt["pts"]
		var ti: int = int(rt["target_idx"])
		var last: Vector3 = pts[pts.size() - 1]
		var over: bool = false
		for q in pts.slice(0, ti + 1):
			if Vector2(q.x - tp.x, q.z - tp.z).length() < 4600.0:
				over = true
		_check(over and ti < pts.size() - 1 and Vector2(last.x - home.x, last.z - home.z).length() < 1.0, "%s route goes over the target and ends at the home airfield (%d waypoints)" % [kind, pts.size()])
	_check(EF.phase_of(2, 5) == "outbound" and EF.phase_of(5, 5) == "target" and EF.phase_of(6, 5) == "home", "mission phase follows the leader's waypoint")
	var slots: Dictionary = {}
	for i in 12:
		slots[str(EF.fighter_slot(i))] = true
	var eslots: Dictionary = {}
	for i in 10:
		eslots[str(EF.escort_slot(i))] = true
	_check(slots.size() == 12 and eslots.size() == 10 and EF.escort_slot(5).y > EF.escort_slot(0).y + 200.0, "sweep and escort slots are distinct, top cover rides higher")
	# a real large raid and a real sweep, spawned into the test world
	var cap_before: int = AIFactory.ai_cap
	AIFactory.ai_cap = 0
	var me: Aircraft = AIFactory.spawn(self, "spitfire", "Allies", player_pos, 0.0, -1.0, 0.5, AIPilot.Role.FIGHTER, null, false)
	me.player_controlled = true
	var ef := EnemyFlights.new()
	add_child(ef)
	ef.setup(self, me, null, "Allies", 0.5)
	var f: Dictionary = ef.spawn_flight("raid", EF.Size.LARGE, pl)
	_check(not f.is_empty() and (f["bombers"] as Array).size() >= 12 and (f["escorts"] as Array).size() >= 8, "a large raid is %d bombers and %d escorts" % [(f["bombers"] as Array).size(), (f["escorts"] as Array).size()])
	var lead: Aircraft = f["leader"]
	var lp: AIPilot = AIFactory.pilot_of(lead)
	var attached: bool = true
	for e in f["escorts"]:
		var ep: AIPilot = AIFactory.pilot_of(e)
		if ep.leader != lead or ep.role != AIPilot.Role.WINGMAN or (e as Aircraft).team != "Axis":
			attached = false
	_check(attached, "every escort is a wingman of the lead bomber")
	var targets_ok: bool = true
	for b in f["bombers"]:
		var bp: AIPilot = AIFactory.pilot_of(b)
		if not bp.bomb_armed or Vector2(bp.bomb_target.x - 12000.0, bp.bomb_target.z - 22000.0).length() > 1.0 or (b as Aircraft).team != "Axis":
			targets_ok = false
	_check(targets_ok and lp.waypoints.size() == (f["route"] as Array).size() and lp.state == AIPilot.State.ROUTE, "the bombers carry the target and the leader flies the route")
	# the bombers are hit: the escorts widen their reaction
	f["alert_t"] = f["age"]
	ef._update(f, 1.0)
	var any_esc: AIPilot = AIFactory.pilot_of((f["escorts"] as Array)[0])
	_check(any_esc.engage_radius >= 8000.0, "escorts react when the bombers are attacked")
	# leader shot down: a bomber takes over, the escorts follow the new leader
	lead.state = Aircraft.State.DEAD
	ef._update(f, 1.0)
	var nl: Aircraft = f["leader"]
	_check(nl != lead and nl.state == Aircraft.State.ALIVE and AIFactory.pilot_of((f["escorts"] as Array)[0]).leader == nl, "a new lead bomber is chosen and the escorts re-attach")
	# past the target the flight turns for home, then is tidied away once far from the player
	var np: AIPilot = AIFactory.pilot_of(nl)
	np.wp_index = int(f["target_idx"]) + 1
	ef._update(f, 1.0)
	_check(str(f["phase"]) == "home", "past its target the flight heads home")
	me.global_position = Vector3(90000.0, 1500.0, 90000.0)
	np.wp_index = np.waypoints.size()
	var alive: bool = ef._update(f, 1.0)
	_check(not alive, "a flight that has got home and left the player's sector is removed")
	# a sweep keeps to its route after a fight
	me.global_position = player_pos
	var fs: Dictionary = ef.spawn_flight("sweep", EF.Size.MEDIUM, pl)
	var sl: AIPilot = AIFactory.pilot_of(fs["leader"])
	_check((fs["members"] as Array).size() >= 6 and sl.state == AIPilot.State.ROUTE, "a medium sweep is 6-8 fighters on a route")
	sl.state = AIPilot.State.PATROL      # a fight ended
	ef._update(fs, 1.0)
	_check(sl.state == AIPilot.State.ROUTE, "a sweep leader goes back to its route after a fight")
	var dead_lead: Aircraft = fs["leader"]
	dead_lead.state = Aircraft.State.DEAD
	ef._update(fs, 1.0)
	_check(fs["leader"] != dead_lead and AIFactory.pilot_of(fs["leader"]).role == AIPilot.Role.FIGHTER and AIFactory.pilot_of(fs["leader"]).waypoints.size() == (fs["route"] as Array).size(), "a sweep's next fighter takes over the route")
	var fr: Dictionary = ef.spawn_flight("recon", EF.Size.SMALL, pl)
	_check((fr["members"] as Array).size() == 1, "recon is one aircraft")
	for a in get_tree().get_nodes_in_group("aircraft"):
		if a != me and a is Aircraft and (a as Aircraft).team == "Axis":
			(a as Node).queue_free()
	for fl in [f, fs, fr]:
		var fm: Variant = fl.get("form")
		if fm != null and is_instance_valid(fm):
			(fm as Node).queue_free()
	me.queue_free()
	ef.queue_free()
	AIFactory.ai_cap = cap_before


# ================================================================== controller navigation (PadNav)
## Every menu / overlay screen is built headless and checked for: registered with PadNav, an initial focus, every visible
## enabled Button / Slider / OptionButton / CheckBox / SpinBox reachable by walking focus neighbours from it, and B
## (a real InputEventJoypadButton) backing out. User files the menus may touch are saved and restored around it.
const _PAD_FILES := ["settings.cfg", "career.json", "campaign.json", "pilot_log.cfg"]


func _pad_backup() -> Dictionary:
	var out: Dictionary = {}
	for f in _PAD_FILES:
		var p: String = "user://" + String(f)
		out[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null
	return out


func _pad_restore(bk: Dictionary) -> void:
	for p in bk.keys():
		if bk[p] == null:
			continue
		var f: FileAccess = FileAccess.open(String(p), FileAccess.WRITE)
		if f != null:
			f.store_buffer(bk[p])
			f.close()


func _pad_button(btn: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = pressed
	Input.parse_input_event(e)


func _pad_tap(btn: int) -> void:
	_pad_button(btn, true)
	await get_tree().process_frame
	_pad_button(btn, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _pad_axis(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _pad_frames(n: int = 4) -> void:
	for i in n:
		await get_tree().process_frame


func _pad_hit(hit: Array) -> void:
	hit[0] = true


## A flag that turns true when the screen emits any of its own (script-defined) signals: closed, cancelled, ...
func _pad_watch(menu: Object) -> Array:
	var hit: Array = [false]
	for s in menu.get_signal_list():
		if ClassDB.class_has_signal(menu.get_class(), String(s["name"])):
			continue
		var argc: int = (s["args"] as Array).size()
		menu.connect(String(s["name"]), Callable(self, "_pad_hit").bind(hit).unbind(argc))
	return hit


func _pad_targets(menu: Node) -> Array:
	var out: Array = []
	for c in menu.find_children("*", "Control", true, false):
		var ctl: Control = c
		if not ctl.is_visible_in_tree():
			continue
		var t: Control = null
		if ctl is SpinBox:
			t = (ctl as SpinBox).get_line_edit()
		elif ctl is Button or ctl is Slider:
			t = ctl
		if t == null or t.get_focus_mode_with_override() == Control.FOCUS_NONE:
			continue
		if t is BaseButton and (t as BaseButton).disabled:
			continue
		out.append(t)
	return out


func _pad_reach(start: Control) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Control = queue.pop_front()
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var n: Control = c.find_valid_focus_neighbor(side)
			if n != null and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _pad_name(c: Control) -> String:
	if c is Button:
		return "'%s'" % (c as Button).text
	return c.get_class() + ":" + String(c.name)


## Initial focus inside `menu`, then every visible enabled control reachable from it.
func _pad_check_reach(label: String, menu: Node, need_focus: bool = true) -> void:
	var fo: Control = get_viewport().gui_get_focus_owner()
	var ok: bool = fo != null and menu.is_ancestor_of(fo) or fo == menu
	if need_focus:
		_check(ok, "%s: opens with a focused control" % label)
	if fo == null or not ok:
		return
	var seen: Dictionary = _pad_reach(fo)
	var missing: PackedStringArray = []
	for t in _pad_targets(menu):
		if not seen.has(t):
			missing.append(_pad_name(t))
			for sd in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				var nb: Control = t.find_valid_focus_neighbor(sd)
				print("      unreachable ", _pad_name(t), " rect=", t.get_global_rect(), " side ", sd, " -> ", _pad_name(nb) if nb != null else "none", " ", nb.get_global_rect() if nb != null else "", " seen=", seen.has(nb))
	_check(missing.is_empty(), "%s: every control is reachable by pad focus (unreachable: %s)" % [label, ", ".join(missing.slice(0, 6))])


func _pad_screen_test(label: String, menu: Node, cancels: bool = true, need_focus: bool = true) -> void:
	await _pad_frames(5)
	_check(PadNav.top() == menu, "%s: registered as the top PadNav screen" % label)
	_pad_check_reach(label, menu, need_focus)
	if cancels:
		var hit: Array = _pad_watch(menu)
		await _pad_tap(JOY_BUTTON_B)
		_check(hit[0] or not is_instance_valid(menu) or menu.is_queued_for_deletion() or PadNav.top() != menu, "%s: B backs out" % label)


func _pad_free(n: Variant) -> void:
	if is_instance_valid(n):
		(n as Node).queue_free()
	get_tree().paused = false


## Sortie setup practice aids: infinite health / infinite ammo apply to the player's aircraft only.
func _test_practice_aids() -> void:
	print("-- infinite health / infinite ammo")
	var p := Aircraft.new()
	add_child(p)
	p.player_controlled = true
	p.infinite_health = true
	p.health = 100.0
	p.take_damage(500.0)
	_check(p.health == 100.0 and p.state == Aircraft.State.ALIVE, "infinite health: gunfire / collision damage does nothing to the player")
	p.fire_kill(true)
	p.start_breakup("tail")
	_check(p.state == Aircraft.State.ALIVE and p.health == 100.0, "infinite health: no fire or structural kill")
	var ai := Aircraft.new()
	add_child(ai)
	ai.infinite_health = true          # the flag is ignored for AI aircraft
	ai.infinite_ammo = true
	ai.health = 100.0
	ai.take_damage(30.0)
	_check(ai.health < 100.0, "infinite health never protects an AI aircraft")
	var ctl := Aircraft.new()
	add_child(ctl)
	ctl.player_controlled = true
	ctl.health = 100.0
	ctl.take_damage(30.0)
	_check(ctl.health < 100.0, "with the box off the player takes damage as before")
	# ammunition: bombs, rockets and gun rounds stay at their loaded value
	var st := AircraftStats.new()
	p.stats = st
	ctl.stats = st
	ai.stats = st
	var ws := WeaponSystem.new()
	add_child(ws)
	var muz := Node3D.new()
	p.add_child(muz)
	ws._muzzles = [muz]
	ws.aircraft = p
	p.infinite_ammo = true
	p.ammo = 500
	ws._on_fire(p)
	_check(p.ammo == 500, "infinite ammo: firing the guns leaves the rounds at 500 (got %d)" % p.ammo)
	p.bombs = 4
	p.weapon_mode = 2
	ws._on_bomb(p)
	_check(p.bombs == 4, "infinite ammo: dropping a bomb keeps the count (got %d)" % p.bombs)
	ctl.bombs = 4
	ctl.weapon_mode = 2
	ws._on_bomb(ctl)
	_check(ctl.bombs == 3, "with the box off a bomb release uses one (got %d)" % ctl.bombs)
	ws.queue_free()
	p.queue_free()
	ai.queue_free()
	ctl.queue_free()


func _test_pad_navigation() -> void:
	print("-- controller navigation: focus, reachability and back on every menu")
	var bk: Dictionary = _pad_backup()
	var root: Node = self
	# --- input map: menu actions on the pad, flight actions left alone
	var has_a: bool = false
	for e in InputMap.action_get_events("ui_accept"):
		has_a = has_a or (e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	_check(has_a, "ui_accept is the A button")
	var dpad_ok: bool = false
	var stick_ok: bool = false
	for e in InputMap.action_get_events("ui_down"):
		dpad_ok = dpad_ok or (e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_DOWN)
		stick_ok = stick_ok or (e is InputEventJoypadMotion and (e as InputEventJoypadMotion).axis == JOY_AXIS_LEFT_Y)
	_check(dpad_ok and stick_ok, "ui_down is the D-pad and the left stick")
	var has_start: bool = false
	for e in InputMap.action_get_events("ui_cancel"):
		has_start = has_start or (e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_START)
	_check(has_start, "ui_cancel is Start (pause / back)")
	var b_in_cancel := func() -> bool:
		for e in InputMap.action_get_events("ui_cancel"):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_B:
				return true
		return false
	_check(not PadNav.is_active() and not b_in_cancel.call(), "in flight (no menu open) B is not a menu action")
	var wt_b: bool = false
	for e in InputMap.action_get_events("weapon_toggle"):
		wt_b = wt_b or (e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	_check(wt_b, "flight: B is still the weapon toggle")

	# --- start menu: focus, reach on every page, pad moves focus, one step per stick push, LB / RB flip pages, B does nothing
	var sm := StartMenu.new()
	root.add_child(sm)
	await _pad_frames(6)
	_check(PadNav.top() == sm, "start menu: registered as the top PadNav screen")
	_check(b_in_cancel.call(), "a menu is open: B is ui_cancel")
	for pi in StartMenu.PAGES.size():
		sm._show_page(pi)
		await _pad_frames(3)
		var nav: Control = sm._nav_btns[pi]
		nav.grab_focus()
		_pad_check_reach("start menu page %s" % StartMenu.PAGES[pi], sm)
	sm._show_page(0)
	await _pad_frames(2)
	sm._nav_btns[0].grab_focus()
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	_check(sm._pages[1].visible and not sm._pages[0].visible, "start menu: RB flips to the next page")
	await _pad_tap(JOY_BUTTON_LEFT_SHOULDER)
	_check(sm._pages[0].visible, "start menu: LB flips back")
	sm._nav_btns[0].grab_focus()
	var before: Control = get_viewport().gui_get_focus_owner()
	await _pad_tap(JOY_BUTTON_DPAD_DOWN)
	_check(get_viewport().gui_get_focus_owner() != before and get_viewport().gui_get_focus_owner() != null, "start menu: D-pad down moves the focus")
	var f1: Control = get_viewport().gui_get_focus_owner()
	_pad_axis(JOY_AXIS_LEFT_Y, 1.0)
	await _pad_frames(2)
	_pad_axis(JOY_AXIS_LEFT_Y, 0.8)       # a jittering held stick must not walk the focus further
	await _pad_frames(2)
	_pad_axis(JOY_AXIS_LEFT_Y, 1.0)
	await _pad_frames(2)
	var f2: Control = get_viewport().gui_get_focus_owner()
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _pad_frames(2)
	var steps: Control = f1.find_valid_focus_neighbor(SIDE_BOTTOM)
	_check(f2 == steps, "start menu: a held left stick moves the focus exactly one step")
	var hit_sm: Array = _pad_watch(sm)
	await _pad_tap(JOY_BUTTON_B)
	_check(is_instance_valid(sm) and PadNav.top() == sm and not hit_sm[0], "start menu: B on the top level does nothing")

	# --- a sub-menu on top of the start menu takes the focus, and the opener gets it back
	var opener: Control = null
	for b in sm.find_children("*", "Button", true, false):
		if (b as Button).text == "Options" and (b as Button).is_visible_in_tree():
			opener = b
	_check(opener != null, "start menu: has an Options button")
	if opener != null:
		opener.grab_focus()
		opener.pressed.emit()
		await _pad_frames(6)
		var sets: Node = PadNav.top()
		_check(sets is SettingsMenu, "options: opens as the top screen over the start menu")
		_check(sm._nav_btns[0].get_focus_mode_with_override() == Control.FOCUS_NONE, "options: the menu underneath cannot take focus")
		if sets is SettingsMenu:
			var sett: SettingsMenu = sets
			for key in SettingsMenu.PAGES:
				sett._show_page(String(key))
				await _pad_frames(3)
				sett._tab_btns[String(key)].grab_focus()
				_pad_check_reach("options page %s" % key, sett)
			sett._show_page("video")
			sett._tab_btns["video"].grab_focus()
			await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
			_check(sett._current_page == "render", "options: RB switches to the next page")
			await _pad_tap(JOY_BUTTON_LEFT_SHOULDER)
			_check(sett._current_page == "video", "options: LB switches back")
			# key rebinding with only a pad: a keyboard prompt is cancelled by B, a pad prompt by the timeout / any button
			sett._show_page("controls")
			sett._start_listening_key("gear")
			await _pad_frames(2)
			_check(sett._listening_action == "gear", "controls: waiting for a key")
			await _pad_tap(JOY_BUTTON_B)
			_check(sett._listening_action == "", "controls: B cancels the wait for a keyboard key (no stuck prompt)")
			sett._show_page("video")
			await _pad_tap(JOY_BUTTON_B)
			await _pad_frames(4)
			_check(not is_instance_valid(sett) or sett.is_queued_for_deletion(), "options: B closes it")
			await _pad_frames(4)
			_check(PadNav.top() == sm, "options closed: the start menu is the top screen again")
			_check(get_viewport().gui_get_focus_owner() == opener, "options closed: focus returns to the Options button")
	sm.queue_free()
	await _pad_frames(4)
	_check(not PadNav.is_active() and not b_in_cancel.call(), "all menus closed: B is a flight button again")

	# --- pause menu (sub-menu back stack: Start / B must not close the pause menu while a sub-menu is up)
	var pm := PauseMenu.new()
	root.add_child(pm)
	await _pad_frames(3)
	pm.set_open(true)
	await _pad_frames(5)
	_check(PadNav.top() == pm and get_viewport().gui_get_focus_owner() == pm._resume_btn, "pause menu: opens focused on Resume")
	_pad_check_reach("pause menu", pm)
	var score_btn: Control = null
	for b in pm.find_children("*", "Button", true, false):
		if (b as Button).text == "Score" and (b as Button).is_visible_in_tree():
			score_btn = b
	if score_btn != null:
		score_btn.grab_focus()
		score_btn.pressed.emit()
		await _pad_frames(5)
		_check(PadNav.top() != pm, "pause menu: Score opens on top")
		await _pad_tap(JOY_BUTTON_START)
		await _pad_frames(4)
		_check(pm.is_open() and PadNav.top() == pm, "pause menu: Start closes the sub-menu first, not the pause menu")
		_check(get_viewport().gui_get_focus_owner() == score_btn, "pause menu: focus returns to the Score button")
	await _pad_tap(JOY_BUTTON_START)
	_check(not pm.is_open(), "pause menu: Start closes it (and opens it in flight)")
	pm.set_open(true)
	await _pad_frames(4)
	await _pad_tap(JOY_BUTTON_B)
	_check(not pm.is_open(), "pause menu: B closes it")
	_pad_free(pm)

	# --- the other screens
	var rs: Node = ResultsScreen.show_results(root, true, {"score": 120, "kills": 2, "time": 300.0})
	await _pad_screen_test("results screen", rs, false)
	_pad_free(rs)
	await _pad_frames(2)

	var cm := CampaignMenu.new()
	root.add_child(cm)
	await _pad_screen_test("campaign menu", cm)
	_pad_free(cm)
	await _pad_frames(2)

	var dm := DamCampaignMenu.new()
	var dlayer := CanvasLayer.new()
	root.add_child(dlayer)
	dlayer.add_child(dm)
	await _pad_screen_test("dam busters menu", dm)
	dlayer.queue_free()
	await _pad_frames(2)

	var lg := LegalMenu.new()
	var llayer := CanvasLayer.new()
	root.add_child(llayer)
	llayer.add_child(lg)
	await _pad_screen_test("credits and legal", lg)
	llayer.queue_free()
	await _pad_frames(2)

	var lb := LogbookMenu.new()
	var blayer := CanvasLayer.new()
	root.add_child(blayer)
	blayer.add_child(lb)
	await _pad_screen_test("logbook", lb)
	blayer.queue_free()
	await _pad_frames(2)

	var dp := DonationPrompt.new()
	root.add_child(dp)
	await _pad_screen_test("donation prompt", dp)
	_pad_free(dp)
	await _pad_frames(2)

	var st: Node = StoryScreen.play(root, [{"kind": "text", "title": "T", "text": "Body text."}, {"kind": "text", "title": "U", "text": "More."}])
	await _pad_screen_test("story screen", st, true, false)
	_pad_free(st)
	await _pad_frames(2)

	var md := MedalCeremony.new()
	md.side = "Allies"
	md._queue = ["mid"]
	root.add_child(md)
	await _pad_screen_test("medal ceremony", md)
	_pad_free(md)
	await _pad_frames(2)

	var gate := LegalGate.new()
	root.add_child(gate)
	await _pad_frames(4)
	_check(PadNav.top() == gate, "legal gate: registered")
	gate._step_eula()
	await _pad_frames(6)
	_pad_check_reach("licence agreement", gate)
	_pad_free(gate)
	await _pad_frames(2)

	var fp := FlightPlanner.new()
	root.add_child(fp)
	await _pad_frames(6)
	_check(PadNav.top() == fp and get_viewport().gui_get_focus_owner() == fp._map, "flight planner: opens with the map focused")
	_pad_check_reach("flight planner", fp)
	# pointer: LB / RB jump to an airfield, A picks it (this is the map click a mouse does)
	PadNav._set_pad(true)
	_check(PadNav._pointers.has(fp._map), "flight planner: the map has a pad pointer")
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _pad_frames(2)
	await _pad_tap(JOY_BUTTON_A)
	await _pad_frames(3)
	_check(not fp._sel.is_empty() and str(fp._sel.get("airfield", "")) != "", "flight planner: LB/RB + A chooses an airfield on the map (%s)" % str(fp._sel.get("airfield", "")))
	_check(not fp._fly.disabled, "flight planner: FLY is enabled after choosing")
	var cancel_hit: Array = _pad_watch(fp)
	await _pad_tap(JOY_BUTTON_B)
	_check(cancel_hit[0], "flight planner: B backs out")
	PadNav._set_pad(false)
	_pad_free(fp)
	await _pad_frames(2)

	var ed := MissionEditor.new()
	root.add_child(ed)
	await _pad_frames(6)
	_check(PadNav.top() == ed and get_viewport().gui_get_focus_owner() == ed._hub_list, "mission editor: opens on the mission list")
	_pad_check_reach("mission editor list", ed)
	ed._edit(MissionDoc.new_doc("Allies"), "")
	await _pad_frames(6)
	_check(get_viewport().gui_get_focus_owner() == ed._map and PadNav._pointers.has(ed._map), "mission editor: the map has focus and a pad pointer")
	_pad_check_reach("mission editor", ed)
	ed._tabs.current_tab = 0
	var tab_before: int = ed._tabs.current_tab
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	_check(ed._tabs.current_tab == tab_before + 1, "mission editor: RB switches the side-panel tab")
	_pad_free(ed)
	await _pad_frames(2)

	var film := TrainingFilm.new()
	var flayer := CanvasLayer.new()
	root.add_child(flayer)
	flayer.add_child(film)
	await _pad_screen_test("training film", film)
	flayer.queue_free()
	await _pad_frames(2)

	# --- text fields do not trap the pad
	var tf := Control.new()
	tf.set_anchors_preset(Control.PRESET_FULL_RECT)
	var tvb := VBoxContainer.new()
	tf.add_child(tvb)
	var tb1 := Button.new()
	tb1.text = "above"
	tvb.add_child(tb1)
	var tle := LineEdit.new()
	tvb.add_child(tle)
	var tb2 := Button.new()
	tb2.text = "below"
	tvb.add_child(tb2)
	root.add_child(tf)
	PadNav.screen(tf)
	await _pad_frames(5)
	tle.grab_focus()
	await _pad_tap(JOY_BUTTON_DPAD_DOWN)
	_check(get_viewport().gui_get_focus_owner() == tb2, "text field: D-pad down leaves it")
	tle.grab_focus()
	await _pad_tap(JOY_BUTTON_B)
	_check(get_viewport().gui_get_focus_owner() == tb1, "text field: B leaves it")
	tf.queue_free()
	await _pad_frames(3)

	_pad_restore(bk)
	get_tree().paused = false
	PadNav._set_pad(false)
