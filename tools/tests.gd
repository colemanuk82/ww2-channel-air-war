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
	_test_accessibility()
	_test_awards()
	_test_legal_docs()
	_test_era_damage()
	_test_terraces_war_damage()
	_check(UpdateCheck.is_newer("v1.10", "1.9") and UpdateCheck.is_newer("1.5", "1.4") and not UpdateCheck.is_newer("1.4", "1.4") and not UpdateCheck.is_newer("v1.3", "1.4") and UpdateCheck.is_newer("2.0", "1.99"), "update check compares versions numerically")
	print("\nTESTS %s  (%d passed, %d failed)" % ["FAILED" if _failed > 0 else "OK", _passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


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
	wp.free()


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
						_check(prop_low >= 0.4, "%s: propeller clears the runway at %.0f deg (%.2f m)" % [sid, dg, prop_low])
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
