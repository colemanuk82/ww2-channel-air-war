extends Node3D
## Game root: builds the world (terrain, sea, airfields), shows the start menu, then starts a session:
## player aircraft + camera + HUD + a ModeBase picked from ModeRegistry. Handles pause / results / restart.
##
## Debug args (after `--`): --skip-menu (go straight in)  --mode=dogfight|bombing|ground|free|<id>
##   --side=Allies|Axis  --aircraft=<id>  --difficulty=easy|normal|hard|0..1  --weather=<name>  --time=<preset>
##   --ambient (free flight skirmishes)  --wave=N (dogfight start wave)  --autopilot --ai-debug --quit-after=SECS  --shot=out.png --air --cockpit --noout --frames=N --hawkinge
##   --at=lat,lon,alt,hdg --crash --takeoff --throttle --procedural --warp=N (hold a sim time warp: 1/2/4)
##   --river-test (load the real river network, report it, build one tile's ribbon; then quit)
## Passing --mode= or --shot= implies --skip-menu. Without them the game opens on the start menu.
## Keys: Esc pause, Bksp respawn (free flight), F2 toggle start-airborne, F3 swap airfield, O outlines,
##       R auto-level assist, T time of day, Y weather, H HUD, C camera, ] / [ simulation time warp (x1/x2/x4, F5 too),
##       numpad +/- adjust view distance (chase) / zoom (cockpit), numpad Enter resets that view's distance / zoom.

const HUD_SCENE := "res://scenes/hud.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const AIRCRAFT_SCENE := "res://scenes/aircraft/aircraft_base.tscn"
const CFG_META := "ww2_cfg"
const MENU_META := "ww2_force_menu"

## Core fields built up front. Positions match data/locations.json, so the world populator dresses the same field
## instead of building a second one beside it (Hawkinge, Calais-Marck and Saint-Omer were each doubled up).
const AIRFIELDS := {
	"manston": {"name": "RAF Manston", "lat": 51.3419, "lon": 1.3464, "heading": 100.0},
	"hawkinge": {"name": "RAF Hawkinge", "lat": 51.115, "lon": 1.1494, "heading": 100.0},
	"biggin_hill": {"name": "Biggin Hill", "lat": 51.3308, "lon": 0.0325, "heading": 30.0},
	"tangmere": {"name": "Tangmere", "lat": 50.8472, "lon": -0.7061, "heading": 100.0},
	"kenley": {"name": "Kenley", "lat": 51.3042, "lon": -0.0903, "heading": 70.0},
	"northolt": {"name": "Northolt", "lat": 51.5530, "lon": -0.4181, "heading": 70.0},
	"duxford": {"name": "Duxford", "lat": 52.0908, "lon": 0.1319, "heading": 60.0},
	"westhampnett": {"name": "Westhampnett", "lat": 50.8586, "lon": -0.7503, "heading": 60.0},
	"hornchurch": {"name": "Hornchurch", "lat": 51.5030, "lon": 0.2078, "heading": 70.0},
	"marck": {"name": "Calais-Marck", "lat": 50.9622, "lon": 1.954, "heading": 60.0},
	"st_omer": {"name": "Saint-Omer", "lat": 50.7284, "lon": 2.2556, "heading": 90.0},
	"abbeville_drucat": {"name": "Abbeville-Drucat", "lat": 50.1420, "lon": 1.8320, "heading": 60.0},
	"caen_carpiquet": {"name": "Caen-Carpiquet", "lat": 49.1733, "lon": -0.4505, "heading": 130.0},
	"lille_nord": {"name": "Lille-Nord", "lat": 50.6560, "lon": 3.1000, "heading": 90.0},
	"antwerp_deurne": {"name": "Antwerp-Deurne", "lat": 51.1894, "lon": 4.4603, "heading": 110.0},
}
const SIDE_AIRFIELDS := {
	"Allies": ["manston", "hawkinge", "biggin_hill", "tangmere", "kenley", "northolt", "duxford", "westhampnett", "hornchurch"],
	"Axis": ["marck", "st_omer", "abbeville_drucat", "caen_carpiquet", "lille_nord", "antwerp_deurne"],
}


func _airfield_team(id: String) -> String:
	for side in SIDE_AIRFIELDS:
		if id in SIDE_AIRFIELDS[side]:
			return side
	return "Neutral"

var terrain: TerrainChunkManager
var water: WaterPlane
var _send_off: Node = null      # PlayerGroundCrew on a ground start
var camera_rig: CameraRig
var hud: HUD
var turrets: DefensiveTurrets    # the player bomber's defensive guns (gunner view)
var player: Aircraft
var _want_cockpit := false     # set by --cockpit; re-applied after the pilot binds (see _spawn_player_inner)
var mode: ModeBase
var config: Dictionary = {}
var airfields: Dictionary = {}   # id -> Airfield
var in_game: bool = false

var _respawn_timer: float = -1.0
var _bail: BailOut     # bail-out (J held): the pilot on his parachute; see scripts/bail_out.gd
var _menu: StartMenu
var _pause: PauseMenu
var _results: ResultsScreen
var _menu_anchor: Node3D
var _menu_cam: Camera3D
var _menu_t: float = 0.0
const LOAD_SCREEN_SECONDS := 2.5       # minimum load screen the first time (shaders compile, scenery streams in)
const REPLAY_LOAD_SECONDS := 1.5       # ... and for a replay / next mission: textures and road data are already cached
static var _loaded_once: bool = false
var _args: PackedStringArray = PackedStringArray()
var _rearmed: bool = false


func _ready() -> void:
	GroundKit.lp("main _ready start")
	randomize()
	_args = OS.get_cmdline_user_args()
	HeightField.force_procedural = _args.has("--procedural")
	terrain = TerrainChunkManager.new()
	terrain.name = "Terrain"
	add_child(terrain)
	GroundKit.lp("terrain node (heightfield, imagery)")

	# Airfields (flatten terrain first, then build).
	for id in AIRFIELDS.keys():
		var d: Dictionary = AIRFIELDS[id]
		var wp: Vector3 = WorldCoords.latlon_to_world(d["lat"], d["lon"])
		var y: float = terrain.add_flat_zone(wp, 1000.0, 500.0)
		var af := Airfield.create(d["name"], wp, d["heading"], y)
		af.team = _airfield_team(id)
		af.style = Airfield.style_for(id)
		af.add_to_group("airfield")
		add_child(af)
		airfields[id] = af

	GroundKit.lp("airfields")
	water = WaterPlane.new()
	water.name = "Sea"
	add_child(water)
	GroundKit.lp("water")

	# Ground content (towns, farms, trees, forests, defences) for every mode, not just the ground modes.
	WorldPopulator.populate(self, terrain, airfields)
	GroundKit.lp("WorldPopulator.populate")
	GameState.apply_graphics()
	GroundKit.lp("apply_graphics")
	if _args.has("--reload-test") and not Engine.has_meta("reload_test_done"):   # debug: time a second (replay) load
		Engine.set_meta("reload_test_done", true)
		get_tree().create_timer(9.0).timeout.connect(func() -> void:
			print("[loadprof] ---- reloading scene (a replay) ----")
			get_tree().reload_current_scene())

	var cfg: Dictionary = _initial_config()
	if _args.has("--mission-audit"):     # debug: every mission's objectives / start airfields must resolve and build
		get_tree().create_timer(4.0).timeout.connect(_mission_audit)
	if _args.has("--wingmen-test"):      # debug: report wingmen 5 s after start (use with --plan=...airborne... --wingmen=N)
		get_tree().create_timer(16.0).timeout.connect(func() -> void: print("[wingmen] wanted %d, spawned %d, alive %d" % [mode.wingmen_wanted, mode.wingmen_list.size(), mode.wingmen_list.filter(func(w: Variant) -> bool: return is_instance_valid(w) and (w as Aircraft).state == Aircraft.State.ALIVE).size()]))
	if _args.has("--audio-test"):
		await _audio_test()
		return
	if _args.has("--mem-test"):     # debug: print CPU memory before / after the map data is loaded
		print("[mem] engine+scene at start: %.0f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
		get_tree().create_timer(25.0).timeout.connect(func() -> void:
			print("[mem] after 25 s in a mission: %.0f MB static" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
			print("[mem] nodes %d, objects %d" % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))]))
	if _args.has("--hedge-test"):
		_hedge_test()
		return
	if _args.has("--river-test"):
		_river_test()
		return
	if _args.has("--city-test"):
		_city_test()
		return
	if _args.has("--dock-test"):
		_dock_test()
		return
	if _args.has("--industry-test"):
		_industry_test()
		return
	if _args.has("--landmark-test"):
		_landmark_test()
		return
	if _args.has("--sea-defence-test"):
		_sea_defence_test()
		return
	if _args.has("--balloon-test"):
		_balloon_test()
		return
	if _args.has("--dam-test"):
		_dam_test()
		return
	if _args.has("--decoy-test"):
		_decoy_test()
		return
	if _args.has("--pylon-test"):
		_pylon_test()
		return
	if _args.has("--canal-test"):
		_canal_test()
		return
	if _args.has("--rail-test"):
		_rail_test()
		return
	if _args.has("--airfield-furniture-test"):
		_airfield_furniture_test()
		return
	if _args.has("--oil-test"):
		_oil_test()
		return
	if _args.has("--aircraft-industry-test"):
		_aircraft_industry_test()
		return
	if _args.has("--v-weapons-test"):
		_v_weapons_test()
		return
	if _args.has("--port-clutter-test"):
		_port_clutter_test()
		return
	if _args.has("--rural-test"):
		_rural_test()
		return
	if _args.has("--coastal-landmark-test"):
		_coastal_landmark_test()
		return
	if _args.has("--civil-defence-test"):
		_civil_defence_test()
		return
	if _args.has("--aviation-test"):
		_aviation_test()
		return
	if _args.has("--forestry-test"):
		_forestry_test()
		return
	if _args.has("--navigation-aid-test"):
		_navigation_aid_test()
		return
	if _args.has("--military-depth-test"):
		_military_depth_test()
		return
	if _args.has("--campaign-test"):
		await _campaign_test()
		return
	if _args.has("--planner-test"):
		_planner_test()
		return
	if cfg.is_empty():
		_show_menu()
	else:
		start_game(cfg)


# ---------------------------------------------------------------- config / menu

## Debug (--audio-test): drive the Options > Audio sliders and print the resulting volumes + the saved file section.
func _audio_test() -> void:
	var sm := SettingsMenu.new()
	add_child(sm)
	await get_tree().process_frame
	var sliders: Array = sm.find_children("*", "HSlider", true, false)
	print("[audio-test] sliders found: %d" % sliders.size())
	var vals: Array = [100, 80, 60, 40, 20]
	for i in sliders.size():
		(sliders[i] as HSlider).value = vals[i]
	print("[audio-test] master %.2f fx %.2f engine %.2f radio %.2f music %.2f" % [AudioManager.master_volume, AudioManager.fx_volume, AudioManager.engine_volume, AudioManager.radio_volume, AudioManager.music_volume])
	GameState.save_settings()
	var cf := ConfigFile.new()
	cf.load(GameState.SETTINGS_PATH)
	print("[audio-test] saved [audio]: ", [cf.get_value("audio", "master"), cf.get_value("audio", "fx"), cf.get_value("audio", "engine"), cf.get_value("audio", "radio"), cf.get_value("audio", "music")])
	# restore defaults so the test does not change the player's mix
	GameState.vol_master = 1.0
	GameState.vol_fx = 1.0
	GameState.vol_engine = 1.0
	GameState.vol_radio = 1.0
	GameState.vol_music = 0.7
	GameState.save_settings()
	get_tree().quit()


## Debug (--menu-test)
func _menu_test() -> void:
	var hist_idx: int = _menu._mode_ids.find("historical")
	_menu._mode.select(hist_idx)
	_menu._mode.item_selected.emit(hist_idx)
	for mid in ["bob_kent", "op_axis_reich_defence", "op_waal_crossing", "dday_1944", "dunkirk_first_light"]:
		var i: int = _menu._mission_ids.find(mid)
		_menu._mission.select(i)
		_menu._mission.item_selected.emit(i)
		print("[menu-test] %-42s -> side %s, aircraft %s" % [mid, _menu._side.get_item_text(_menu._side.selected), _menu._aircraft.get_item_text(_menu._aircraft.selected)])
	for l in _menu.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("v") and (l as Label).text.length() < 8:
			print("[menu-test] version label: ", (l as Label).text)
	get_tree().quit()


## Debug (--hedge-test): how many 22 m samples near a field boundary yield a hedge segment whose ends lie on the boundary.
func _hedge_test() -> void:
	var c: Vector3 = WorldCoords.latlon_to_world(51.63, 5.0)
	var near: int = 0
	var good: int = 0
	var worst: float = 0.0
	var total: int = 0
	for j in 60:
		for i in 60:
			var p := Vector2(c.x + float(i) * 22.0, c.z + float(j) * 22.0)
			total += 1
			var e: Dictionary = Scatter.field_edge(p)
			if e.is_empty() or float(e["dist"]) > 11.0:
				continue
			near += 1
			var q: Vector2 = e["q"]
			var tg: Vector2 = e["tan"]
			var ok: bool = true
			for t in [-1.0, -0.5, 0.5, 1.0]:
				var pe: Dictionary = Scatter.field_edge(q + tg * (13.0 * t))
				worst = maxf(worst, float(pe["dist"]))
				if float(pe["dist"]) > 2.2:
					ok = false
			if ok:
				good += 1
	print("[hedge] %d samples, %d within 11 m of a boundary, %d give a full 26 m segment (%.0f%%), worst end offset %.1f m" % [total, near, good, 100.0 * good / maxf(near, 1), worst])
	get_tree().quit()


## Debug (--river-test): load the real river network, report it, and build one tile's ribbon at a known point.
func _river_test() -> void:
	RiverMesh.ensure_loaded()
	print("[river] %d lines, %.0f km loaded (real_rivers global %s)" % [RiverMesh.line_count(), RiverMesh.total_km(), "on" if RiverMesh.has_rivers() else "off"])
	var wp: Vector3 = WorldCoords.latlon_to_world(51.49, 0.15)          # the Thames at Greenwich reach
	var tile: float = WorldPopulator.TILE
	var org := Vector2(floorf(wp.x / tile) * tile, floorf(wp.z / tile) * tile)
	var drawn: int = 0
	var verts: int = 0
	if RiverMesh.has_rivers():
		RiverMesh.prepare_block(org, tile)
		var mi: MeshInstance3D = RiverMesh.build_tile(org, tile)
		RiverMesh.clear_block()
		if mi != null:
			drawn = 1
			verts = (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("[river] tile at (51.49, 0.15) -> world (%.0f, %.0f), origin (%.0f, %.0f): %d tile(s) drawn, %d verts" % [wp.x, wp.z, org.x, org.y, drawn, verts])
	get_tree().quit()


## Debug (--city-test): street-driven town fabric. For every city print its size, street lines found in the town
## radius, houses placed, the longest single terrace run, the district split and the civic-core count.
func _city_test() -> void:
	RoadMesh.ensure_loaded()
	TransportNetwork.ensure_loaded()
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		print("[city] data/locations.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[city] locations.json did not parse")
		get_tree().quit()
		return
	var n_cities: int = 0
	var total_streets: int = 0
	var total_houses: int = 0
	var longest_any: int = 0
	for c in (d as Dictionary).get("cities", []):
		var dd: Dictionary = c
		if not bool(dd.get("in_bounds", true)):
			continue
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		var size: int = int(dd["size"])
		var st: Dictionary = Scatter.town_stats(pos, size, hash(str(dd["id"])) + 77)
		n_cities += 1
		total_streets += int(st["streets"])
		total_houses += int(st["houses"])
		longest_any = maxi(longest_any, int(st["longest_run"]))
		print("[city] %-16s size %d  streets %3d  houses %4d  longest run %3d  core %3d  suburb %3d  industrial %3d  civic %d  waterfront %s" % [
			str(dd["id"]), size, int(st["streets"]), int(st["houses"]), int(st["longest_run"]),
			int(st["core"]), int(st["suburban"]), int(st["industrial"]), int(st["civic"]),
			"yes" if bool(st["waterfront"]) else "no"])
	print("[city] %d cities, %d street lines, %d houses total, longest run %d" % [n_cities, total_streets, total_houses, longest_any])
	get_tree().quit()


## Debug (--dock-test): build one of every typed waterfront structure (3.1) at a known lat/lon and report mesh /
## ship counts, then the number of pier/dock sites registered from data/docks_1940.json. Does not start a mission.
func _dock_test() -> void:
	var cases: Array = [
		["pleasure_pier", 50.8156, -0.1368, 2, "Allies"],
		["dock_basin", 51.508, 0.025, 3, "Allies"],
		["drydock_shipyard", 50.802, -1.106, 3, "Allies"],
		["river_quay", 51.49, 0.15, 2, "Allies"],
		["fishing_harbour", 50.83, -0.245, 1, "Allies"],
	]
	for c in cases:
		var kind: String = str(c[0])
		var wp: Vector3 = WorldCoords.latlon_to_world(float(c[1]), float(c[2]))
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var shore: Array = Scatter.find_shore(wp, 1600.0, 8, rng)
		var pos: Vector3 = wp
		var sea: Vector3 = GroundKit.water_dir(wp, 900.0)
		if not shore.is_empty():
			var best: Dictionary = shore[0]
			for sd in shore:
				if (sd["pos"] as Vector3).distance_to(wp) < (best["pos"] as Vector3).distance_to(wp):
					best = sd
			pos = best["pos"]
			sea = best["sea"]
		if sea == Vector3.ZERO:
			sea = Vector3(0, 0, -1)
		var n: Node3D = null
		match kind:
			"pleasure_pier":
				n = WorldFeatures.build_pleasure_pier(pos, sea, int(c[3]), str(c[4]), 777)
			"dock_basin":
				n = WorldFeatures.build_dock_basin(pos, sea, int(c[3]), str(c[4]), 777)
			"drydock_shipyard":
				n = WorldFeatures.build_drydock_shipyard(pos, sea, int(c[3]), str(c[4]), 777)
			"river_quay":
				n = WorldFeatures.build_river_quay(pos, Vector3(-sea.z, 0.0, sea.x), int(c[3]), str(c[4]), 777)
			"fishing_harbour":
				n = WorldFeatures.build_fishing_harbour(pos, sea, int(c[3]), str(c[4]), 777)
		print("[dock] %-16s at (%.0f, %.0f) sea (%.2f, %.2f) -> %d meshes, %d ships" % [kind, pos.x, pos.z, sea.x, sea.z, _count_meshes(n), _count_ships(n)])
	if WorldPopulator.instance != null:
		print("[dock] %d pier/dock sites registered from data/docks_1940.json" % WorldPopulator.instance.dock_sites)
	get_tree().quit()


## Debug (--industry-test): build one of every kind in data/industry_1940.json (Phase 4.1 IndustryKit) at a known
## lat/lon, plus a rail siding stub each, and report mesh / chimney-emitter counts. Then print how many industry
## sites registered. Engine-free smoke test - does not start a mission.
func _industry_test() -> void:
	var cases: Array = [
		["gasworks", 51.52, 0.055, 3, "Allies"],
		["colliery", 52.72, -2.0, 2, "Allies"],
		["mill", 52.64, -1.14, 2, "Allies"],
		["brewery", 52.8, -1.63, 3, "Allies"],
		["power_station", 51.481, -0.146, 3, "Allies"],
		["shipyard", 51.505, -0.015, 2, "Allies"],
		["dockyard", 51.46, 0.35, 3, "Allies"],
		["goods_yard", 51.53, -0.24, 2, "Allies"],
		["engine_shed", 52.92, -1.47, 3, "Allies"],
		["waterworks", 51.56, -0.05, 2, "Allies"],
		["cement_works", 51.44, 0.33, 2, "Allies"],
		["staithes", 51.5, 0.02, 1, "Allies"],
	]
	var kinds_ok: int = 0
	for c in cases:
		var kind: String = str(c[0])
		var wp: Vector3 = WorldCoords.latlon_to_world(float(c[1]), float(c[2]))
		var n: Node3D = IndustryKit.build(kind, wp, 0.0, int(c[3]), str(c[4]), 4242 + kinds_ok)
		if n == null:
			print("[industry] %-14s NULL BUILDER" % kind)
			continue
		var rail: Vector3 = wp + Vector3(220.0, 0.0, 120.0)
		var sid: Node3D = IndustryKit.build_siding(wp, rail, 99)
		var meshes: int = _count_meshes(n) + _count_meshes(sid)
		var emitters: int = _count_emitters(n)
		if n.get_child_count() > 0:
			kinds_ok += 1
		print("[industry] %-14s at (%.0f, %.0f) size %d -> %d meshes (%d works + %d siding), %d chimney emitters" % [kind, wp.x, wp.z, int(c[3]), meshes, _count_meshes(n), _count_meshes(sid), emitters])
	print("[industry] %d/%d kinds built from IndustryKit" % [kinds_ok, cases.size()])
	if WorldPopulator.instance != null:
		print("[industry] %d industry sites registered from data/industry_1940.json" % WorldPopulator.instance.industry_sites.size())
	get_tree().quit()


## Debug (--landmark-test): build EVERY landmark id - the compiled build() cases in landmarks.gd reachable from
## data/locations.json features[] plus the ids in data/landmarks_1940.json - assert a non-null node and count its
## meshes. Engine-free smoke test; prints a pass/fail tally and any id that returns null or has zero meshes.
func _landmark_test() -> void:
	var ids: Array = []
	var lf: FileAccess = FileAccess.open("res://data/landmarks_1940.json", FileAccess.READ)
	if lf != null:
		var ld: Variant = JSON.parse_string(lf.get_as_text())
		lf = null
		if ld is Dictionary:
			for e in (ld as Dictionary).get("landmarks", []):
				ids.append(str((e as Dictionary).get("id", "")))
	var lc: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if lc != null:
		var cd: Variant = JSON.parse_string(lc.get_as_text())
		lc = null
		if cd is Dictionary:
			for f in (cd as Dictionary).get("features", []):
				if str((f as Dictionary).get("type", "")) == "landmark":
					ids.append(str((f as Dictionary).get("id", "")))
	var seen: Dictionary = {}
	var passed: int = 0
	var failed: int = 0
	for id in ids:
		var lm_id: String = str(id)
		if lm_id.is_empty() or seen.has(lm_id):
			continue
		seen[lm_id] = true
		var n: Node3D = Landmarks.build(lm_id)
		if n == null:
			failed += 1
			print("[landmark] %-34s FAIL (build() returned null)" % lm_id)
			continue
		var meshes: int = _count_meshes(n)
		if meshes == 0:
			failed += 1
			print("[landmark] %-34s FAIL (0 meshes)" % lm_id)
		else:
			passed += 1
			print("[landmark] %-34s ok  %3d meshes" % [lm_id, meshes])
	print("[landmark] %d/%d ids built, %d failed" % [passed, seen.size(), failed])
	get_tree().quit()


## Debug (--sea-defence-test): build one of every sea-defence kind (P1) from data/sea_defences_1940.json at its
## real position, count meshes, and print how many sites registered + the total spanned km. Engine-free smoke test.
func _sea_defence_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/sea_defences_1940.json", FileAccess.READ)
	if f == null:
		print("[seadef] data/sea_defences_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[seadef] sea_defences_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var built: int = 0
	var empty: int = 0
	var total_m: float = 0.0
	for e in sites:
		var r: Dictionary = e
		var kind: String = str(r.get("kind", ""))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var length_m: float = float(r.get("length_m", 0.0))
		var n: Node3D = SeaDefenceKit.build(kind, str(r.get("style", "")), pos, float(r.get("heading_deg", 0.0)), length_m, int(r.get("rows", 1)), hash(str(r.get("id", ""))))
		var meshes: int = _count_meshes(n)
		if meshes >= 1:
			built += 1
		else:
			empty += 1
			print("[seadef] %-26s FAIL (0 meshes)" % str(r.get("id", "?")))
		if kind in ["minefield", "boom", "obstacles"]:
			total_m += length_m
		print("[seadef] %-26s %-9s at (%.0f, %.0f) -> %4d meshes" % [str(r.get("id", "?")), kind, pos.x, pos.z, meshes])
		n.free()
	print("[seadef] %d/%d sea-defence sites built non-null, %d empty, %.1f km of barrier spanned" % [built, sites.size(), empty, total_m / 1000.0])
	if WorldPopulator.instance != null:
		print("[seadef] %d sea-defence sites registered, %.1f km spanned" % [WorldPopulator.instance.sea_defence_sites, WorldPopulator.instance.sea_defence_km])
	get_tree().quit()


## Debug (--balloon-test): the city balloon barrage (P2). For every city print its barrage size, then the
## per-size totals and the London-vs-town check. Uses the pure WorldPopulator.city_balloon_plan().
func _balloon_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		print("[balloon] data/locations.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[balloon] locations.json did not parse")
		get_tree().quit()
		return
	var by_size: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	var cities: int = 0
	var total: int = 0
	var london: int = 0
	var town1: int = 0
	for c in (d as Dictionary).get("cities", []):
		var dd: Dictionary = c
		if not bool(dd.get("in_bounds", true)):
			continue
		var id: String = str(dd["id"])
		var size: int = int(dd["size"])
		if size < 1 or size > 5:
			continue
		var pos: Vector3 = WorldCoords.latlon_to_world(float(dd["lat"]), float(dd["lon"]))
		var radius: float = 90.0 + float(size) * 85.0
		var n: int = WorldPopulator.city_balloon_plan(pos, id, size, radius * 1.25).size()
		cities += 1
		total += n
		by_size[size] = int(by_size[size]) + n
		if id == "london":
			london = n
		if size == 1:
			town1 = maxi(town1, n)
	print("[balloon] %d cities covered, %d balloons total" % [cities, total])
	print("[balloon] per size band: 1=%d 2=%d 3=%d 4=%d 5=%d" % [int(by_size[1]), int(by_size[2]), int(by_size[3]), int(by_size[4]), int(by_size[5])])
	print("[balloon] London=%d, biggest size-1 town=%d -> %s" % [london, town1, "OK (London denser)" if london > town1 else "FAIL"])
	get_tree().quit()


## Debug (--dam-test): build every Dam Busters dam (P3) from data/dams_1940.json - DamKit scenery plus the
## destructible GroundStructure("dam") wall - and print mesh counts + reservoir area. Engine-free smoke test.
func _dam_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/dams_1940.json", FileAccess.READ)
	if f == null:
		print("[dam] data/dams_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[dam] dams_1940.json did not parse")
		get_tree().quit()
		return
	var dams: Array = (d as Dictionary).get("dams", [])
	var ok: int = 0
	var fails: Array = []
	var total_km2: float = 0.0
	for e in dams:
		var r: Dictionary = e
		var id: String = str(r.get("id", ""))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var scenery: Node3D = DamKit.build(id)
		var smeshes: int = _count_meshes(scenery)
		var wall: GroundStructure = GroundStructure.create("dam", str(r.get("team", "Axis")), pos, float(r.get("heading_deg", 0.0)))
		add_child(wall)                                  # GroundStructure builds its meshes in _ready()
		var wmeshes: int = _count_meshes(wall)
		var area: float = float(r.get("reservoir_km2", 0.0))
		total_km2 += area
		if smeshes >= 1 and wmeshes >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[dam] %-8s at (%.0f, %.0f) -> %3d scenery meshes + %3d wall meshes, %.2f km2 reservoir" % [id, pos.x, pos.z, smeshes, wmeshes, area])
		scenery.free()
		remove_child(wall)
		wall.free()
	print("[dam] %d/%d dams built non-null with >= 1 mesh (%d failed: %s); %.1f km2 of reservoir total" % [ok, dams.size(), fails.size(), ", ".join(PackedStringArray(fails)), total_km2])
	if WorldPopulator.instance != null:
		print("[dam] %d dam sites registered" % WorldPopulator.instance.dam_sites)
	get_tree().quit()


## Debug (--decoy-test): build one of every decoy kind (P4) from data/decoys_1940.json at its real position,
## count meshes, and build each decoy's destructible GroundStructure("decoy") target. Engine-free smoke test.
func _decoy_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/decoys_1940.json", FileAccess.READ)
	if f == null:
		print("[decoy] data/decoys_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[decoy] decoys_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var empty: int = 0
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", ""))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var scenery: Node3D = DecoyKit.build(kind, pos, float(r.get("heading_deg", 0.0)), int(r.get("size", 1)), hash(id))
		var sm: int = _count_meshes(scenery)
		var target: GroundStructure = GroundStructure.create("decoy", str(r.get("team", "Allies")), pos, float(r.get("heading_deg", 0.0)))
		add_child(target)
		var tm: int = _count_meshes(target)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if sm >= 1 and tm >= 1:
			ok += 1
		else:
			empty += 1
			print("[decoy] %-18s FAIL (scenery %d, target %d meshes)" % [id, sm, tm])
		print("[decoy] %-18s %-9s at (%.0f, %.0f) -> %3d scenery + %3d target meshes" % [id, kind, pos.x, pos.z, sm, tm])
		scenery.free()
		remove_child(target)
		target.free()
	print("[decoy] kinds: %s" % [kinds])
	print("[decoy] %d/%d decoy sites built with >= 1 mesh (%d empty)" % [ok, sites.size(), empty])
	if WorldPopulator.instance != null:
		print("[decoy] %d decoy sites registered as raid ('decoy') targets" % WorldPopulator.instance.decoy_sites)
	get_tree().quit()


## Debug (--pylon-test): the P5 power grid. Prints the loaded line count / km / approximate pylon count and
## whether the data came from the real OSM fetch or the curated period-grid fallback, then builds a couple of
## sample tiles and counts the pylons and telegraph poles placed. Engine-free smoke test.
func _pylon_test() -> void:
	PylonMesh.ensure_loaded()
	print("[pylon] source: %s" % ("osm/overpass (data/osm/power.json)" if PylonMesh.sourced_osm else "curated fallback (data/pylons_1940.json)"))
	print("[pylon] %d lines, %.1f km, ~%d pylons" % [PylonMesh.line_count(), PylonMesh.total_km(), PylonMesh.pylon_total()])
	var centres: Array = [[51.51, -0.12], [51.75, 0.05], [51.44, 0.34], [52.06, 1.15]]
	var tot_pyl: int = 0
	var tot_pole: int = 0
	for c in centres:
		var w: Vector3 = WorldCoords.latlon_to_world(float(c[0]), float(c[1]))
		var org := Vector2(w.x - WorldPopulator.TILE * 0.5, w.z - WorldPopulator.TILE * 0.5)
		var n: Node3D = PylonMesh.build_tile(org, WorldPopulator.TILE)
		var py: int = 0
		var po: int = 0
		if n != null:
			py = _count_instances_named(n, "pylons")
			po = _count_instances_named(n, "poles")
		tot_pyl += py
		tot_pole += po
		print("[pylon] tile @(%.2f,%.2f) -> %d pylons + %d telegraph poles" % [float(c[0]), float(c[1]), py, po])
		if n != null:
			n.free()
	print("[pylon] sample tiles: %d pylons, %d poles" % [tot_pyl, tot_pole])
	get_tree().quit()


## Debug (--canal-test): the P6 canal furniture. Prints the canal line count / km and builds a spread of
## sample tiles over known canal country, counting furniture meshes. Engine-free smoke test.
func _canal_test() -> void:
	CanalKit.ensure_loaded()
	print("[canal] %d canal lines, %.1f km from data/osm/rivers.json (k='canal')" % [CanalKit.canal_count(), CanalKit.total_km()])
	var centres: Array = [[51.45, -0.97], [51.64, -0.47], [52.06, -1.33], [52.48, -1.90], [52.63, -1.13], [51.53, -0.13], [51.35, -1.99]]
	var tot: int = 0
	var hit: int = 0
	for c in centres:
		var w: Vector3 = WorldCoords.latlon_to_world(float(c[0]), float(c[1]))
		var org := Vector2(w.x - WorldPopulator.TILE * 0.5, w.z - WorldPopulator.TILE * 0.5)
		var n: Node3D = CanalKit.build_tile(org, WorldPopulator.TILE)
		var m: int = 0
		if n != null:
			m = _count_meshes(n)
			hit += 1
		tot += m
		print("[canal] tile @(%.2f,%.2f) -> %d furniture pieces (%d meshes)" % [float(c[0]), float(c[1]), (n.get_child_count() if n != null else 0), m])
		if n != null:
			n.free()
	print("[canal] %d/%d sample tiles carried canal furniture; %d meshes total" % [hit, centres.size(), tot])
	get_tree().quit()


## Debug (--rail-test): the P7 railway drama. Prints the rail line count / km and the curated catalogue, builds one
## of every furniture kind, and builds a spread of sample tiles over known rail country (the viaduct/tunnel
## terrain derivations run inside build_tile), counting meshes. Engine-free smoke test.
func _rail_test() -> void:
	RailKit.ensure_loaded()
	print("[rail] %d rail lines, %.0f km from data/osm/rails.json; %d curated viaducts/tunnels" % [RailKit.rail_count(), RailKit.total_km(), RailKit.catalog_count()])
	var pos: Vector3 = WorldCoords.latlon_to_world(51.5, -0.1)
	var fails: Array = []
	var nkinds: int = RailKit.kinds().size()
	for k in RailKit.kinds():
		var n: Node3D = RailKit.build_piece(String(k), pos, 0.0, 7)
		var m: int = _count_meshes(n)
		if m < 1:
			fails.append(String(k))
		print("[rail] piece %-14s -> %3d meshes" % [String(k), m])
		n.free()
	print("[rail] %d/%d furniture kinds built >= 1 mesh (%s)" % [nkinds - fails.size(), nkinds, "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	var centres: Array = [[51.51, -0.12], [51.51, 0.10], [51.75, -0.19], [52.33, -1.16], [51.42, -2.23], [51.03, 0.05], [50.90, -1.40], [51.03, 2.33]]
	var tot: int = 0
	var hit: int = 0
	for c in centres:
		var w: Vector3 = WorldCoords.latlon_to_world(float(c[0]), float(c[1]))
		var org := Vector2(w.x - WorldPopulator.TILE * 0.5, w.z - WorldPopulator.TILE * 0.5)
		var n2: Node3D = RailKit.build_tile(org, WorldPopulator.TILE)
		var m2: int = 0
		if n2 != null:
			m2 = _count_meshes(n2)
			hit += 1
		tot += m2
		print("[rail] tile @(%.2f,%.2f) -> %d pieces (%d meshes)" % [float(c[0]), float(c[1]), (n2.get_child_count() if n2 != null else 0), m2])
		if n2 != null:
			n2.free()
	print("[rail] %d/%d sample tiles carried railway furniture; %d meshes total" % [hit, centres.size(), tot])
	if WorldPopulator.instance != null:
		print("[rail] %d curated rail structures registered" % WorldPopulator.instance.rail_drama_sites)
	get_tree().quit()


## Debug (--airfield-furniture-test): the P8 airfield furniture. Dresses a few of the real airfields from
## data/locations.json with AirfieldFurniture and counts the meshes and destructible prop nodes placed.
func _airfield_furniture_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if f == null:
		print("[airfield-furn] data/locations.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[airfield-furn] locations.json did not parse")
		get_tree().quit()
		return
	var airs: Array = (d as Dictionary).get("airfields", [])
	var done: int = 0
	var tot_meshes: int = 0
	for e in airs:
		if done >= 6:
			break
		var a: Dictionary = e
		if not bool(a.get("in_bounds", true)):
			continue
		var id: String = str(a["id"])
		var pos: Vector3 = WorldCoords.latlon_to_world(float(a["lat"]), float(a["lon"]))
		var af: Airfield = Airfield.create(str(a.get("name", id)), pos, float(a.get("heading_deg", 0.0)), GroundKit.ground_y(pos.x, pos.z))
		af.style = Airfield.style_for(id)
		add_child(af)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var container := Node3D.new()
		var axf := Transform3D(Basis(Vector3.UP, af.rotation.y), af.position)
		AirfieldFurniture.dress(container, af, axf, af.surface_y, "Allies", rng)
		add_child(container)
		var m: int = _count_meshes(container)
		var props: int = container.find_children("*", "AirfieldProp", true, false).size()
		tot_meshes += m
		done += 1
		print("[airfield-furn] %-18s (%s) -> %3d meshes, %d prop clusters" % [id, af.style, m, props])
		remove_child(container)
		container.free()
		remove_child(af)
		af.free()
	print("[airfield-furn] %d airfields dressed, %d meshes total" % [done, tot_meshes])
	get_tree().quit()


## Debug (--oil-test): the P9 oil and fuel sites. Builds every site from data/oil_fuel_1940.json - OilFuelKit
## scenery plus its destructible GroundStructure - and prints mesh counts and the kinds covered. Engine-free.
func _oil_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/oil_fuel_1940.json", FileAccess.READ)
	if f == null:
		print("[oil] data/oil_fuel_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[oil] oil_fuel_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "oil_depot"))
		var team: String = str(r.get("team", "Allies"))
		var size: int = int(r.get("size", 2))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var scenery: Node3D = OilFuelKit.build(kind, pos, 0.0, size, team, hash(id))
		var sm: int = _count_meshes(scenery)
		var st: GroundStructure = GroundStructure.create(WorldPopulator._oil_structure_kind(kind), team, pos, 0.0)
		add_child(st)
		var tm: int = _count_meshes(st)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if sm >= 1 and tm >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[oil] %-16s %-11s size %d at (%.0f, %.0f) -> %3d scenery + %3d structure meshes" % [id, kind, size, pos.x, pos.z, sm, tm])
		scenery.free()
		remove_child(st)
		st.free()
	print("[oil] kinds: %s" % [kinds])
	print("[oil] %d/%d oil/fuel sites built scenery + a structure with >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[oil] %d oil/fuel sites registered" % WorldPopulator.instance.oil_fuel_sites)
	get_tree().quit()


## Debug (--aircraft-industry-test): the P10 aircraft-industry sites. Builds every site from
## data/aircraft_industry_1940.json - AircraftIndustryKit scenery plus its destructible GroundStructure - and
## prints mesh counts and the kinds covered. Engine-free smoke test.
func _aircraft_industry_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/aircraft_industry_1940.json", FileAccess.READ)
	if f == null:
		print("[aircraft] data/aircraft_industry_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[aircraft] aircraft_industry_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "assembly_plant"))
		var team: String = str(r.get("team", "Allies"))
		var size: int = int(r.get("size", 2))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var scenery: Node3D = AircraftIndustryKit.build(kind, pos, 0.0, size, team, hash(id))
		var sm: int = _count_meshes(scenery)
		var st: GroundStructure = GroundStructure.create("factory", team, pos, 0.0)
		add_child(st)
		var tm: int = _count_meshes(st)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if sm >= 1 and tm >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[aircraft] %-26s %-15s size %d at (%.0f, %.0f) -> %3d scenery + %3d structure meshes" % [id, kind, size, pos.x, pos.z, sm, tm])
		scenery.free()
		remove_child(st)
		st.free()
	print("[aircraft] kinds: %s" % [kinds])
	print("[aircraft] %d/%d aircraft-industry sites built scenery + a structure with >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[aircraft] %d aircraft-industry sites registered" % WorldPopulator.instance.aircraft_industry_sites)
	get_tree().quit()


## Debug (--v-weapons-test): the P11 V-weapon sites. Builds every site from data/v_weapons_1940.json -
## VWeaponsKit scenery plus its destructible GroundStructure("v1_site") (the dome variant for a Heavy Cross
## bunker) - and prints mesh counts and the kinds covered. Engine-free smoke test.
func _v_weapons_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/v_weapons_1940.json", FileAccess.READ)
	if f == null:
		print("[v-weapons] data/v_weapons_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[v-weapons] v_weapons_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "ski_site"))
		var team: String = str(r.get("team", "Axis"))
		var size: int = int(r.get("size", 2))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var scenery: Node3D = VWeaponsKit.build(kind, pos, 0.0, size, team, hash(id))
		var sm: int = _count_meshes(scenery)
		var st: GroundStructure = GroundStructure.create("v1_site", team, pos, 0.0)
		if kind == "heavy_cross":
			st.variant = "dome"
		add_child(st)
		var tm: int = _count_meshes(st)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if sm >= 1 and tm >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[v-weapons] %-24s %-12s size %d at (%.0f, %.0f) -> %3d scenery + %3d structure meshes" % [id, kind, size, pos.x, pos.z, sm, tm])
		scenery.free()
		remove_child(st)
		st.free()
	print("[v-weapons] kinds: %s" % [kinds])
	print("[v-weapons] %d/%d V-weapon sites built scenery + a structure with >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[v-weapons] %d V-weapon sites registered" % WorldPopulator.instance.v_weapon_sites)
	get_tree().quit()


## Debug (--port-clutter-test): the P12 port clutter. Builds every site from data/port_clutter_1940.json -
## PortClutterKit scenery + moored GroundShip hulls - plus the Dover-Dunkerque train-ferry lane, and prints the
## mesh / ship counts and the kinds covered. Engine-free smoke test.
func _port_clutter_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/port_clutter_1940.json", FileAccess.READ)
	if f == null:
		print("[port-clutter] data/port_clutter_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[port-clutter] port_clutter_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var sea := Vector3(0.0, 0.0, -1.0)
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	var ships: int = 0
	var terminals: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "crane"))
		var team: String = str(r.get("team", "Allies"))
		var size: int = int(r.get("size", 2))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = PortClutterKit.build(kind, pos, sea, size, team, hash(id))
		add_child(n)
		var m: int = _count_meshes(n)
		var sh: int = _count_ships(n)
		ships += sh
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		if kind == "train_ferry":
			terminals.append(pos)
		print("[port-clutter] %-20s %-14s size %d at (%.0f, %.0f) -> %3d meshes, %d ship(s)" % [id, kind, size, pos.x, pos.z, m, sh])
		remove_child(n)
		n.free()
	if terminals.size() >= 2:
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([terminals[0], (terminals[0] as Vector3).lerp(terminals[1], 0.5), terminals[1]]))
		var ferry: GroundShip = GroundShip.create("ferry", "Allies", rp, 0.0, -1.0)
		add_child(ferry)
		print("[port-clutter] train-ferry lane: %.1f km, one moving ferry" % (rp.length / 1000.0))
		remove_child(ferry)
		ferry.free()
	print("[port-clutter] kinds: %s" % [kinds])
	print("[port-clutter] %d/%d port-clutter sites built >= 1 mesh (%d moored ships) (%s)" % [ok, sites.size(), ships, "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[port-clutter] %d port-clutter sites registered" % WorldPopulator.instance.port_clutter_sites)
	get_tree().quit()


## Debug (--rural-test): the P13 rural / Kentish texture. Builds every site from data/rural_1940.json - RuralKit
## scenery (oast houses, hop gardens, orchards, market gardens, drainage windpumps, sheep folds) - at its real
## position, counts meshes and prints the kinds covered. Engine-free smoke test.
func _rural_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/rural_1940.json", FileAccess.READ)
	if f == null:
		print("[rural] data/rural_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[rural] rural_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "oast_house"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = RuralKit.build(kind, pos, float(r.get("heading_deg", 0.0)), int(r.get("size", 1)), hash(id))
		var m: int = _count_meshes(n)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[rural] %-22s %-14s size %d at (%.0f, %.0f) -> %3d meshes" % [id, kind, int(r.get("size", 1)), pos.x, pos.z, m])
		n.free()
	print("[rural] kinds: %s" % [kinds])
	print("[rural] %d/%d rural sites built >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[rural] %d rural sites registered" % WorldPopulator.instance.rural_sites)
	get_tree().quit()


## Debug (--coastal-landmark-test): the P14 coastal / seaside landmarks. Builds every site from
## data/coastal_landmarks_1940.json via the new landmarks.gd build() ids (Martello towers, coastguard + RNLI
## stations, lidos, bandstands, requisitioned holiday camps), counts meshes and prints the kinds covered.
func _coastal_landmark_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/coastal_landmarks_1940.json", FileAccess.READ)
	if f == null:
		print("[coast-lm] data/coastal_landmarks_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[coast-lm] coastal_landmarks_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "martello_tower"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = Landmarks.build(kind)
		var m: int = 0
		if n != null:
			m = _count_meshes(n)
			n.free()
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[coast-lm] %-24s %-18s size %d at (%.0f, %.0f) -> %3d meshes" % [id, kind, int(r.get("size", 1)), pos.x, pos.z, m])
	print("[coast-lm] kinds: %s" % [kinds])
	print("[coast-lm] %d/%d coastal landmarks built >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[coast-lm] %d coastal landmarks registered" % WorldPopulator.instance.coastal_landmark_sites)
	get_tree().quit()


## Debug (--civil-defence-test): the P15 civil defence. Builds every site from data/civil_defence_1940.json via
## CivilDefenceKit (surface + Anderson shelters, ARP posts, sandbagged buildings), builds a camouflage-painted
## factory roof, and prints the mesh counts and kinds covered. Engine-free smoke test.
func _civil_defence_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/civil_defence_1940.json", FileAccess.READ)
	if f == null:
		print("[civil-def] data/civil_defence_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[civil-def] civil_defence_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "surface_shelter"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = CivilDefenceKit.build(kind, pos, float(hash(id) % 360), int(r.get("size", 1)), hash(id))
		var m: int = _count_meshes(n)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[civil-def] %-26s %-18s size %d at (%.0f, %.0f) -> %3d meshes" % [id, kind, int(r.get("size", 1)), pos.x, pos.z, m])
		n.free()
	var camp: Node3D = CivilDefenceKit.camouflage_roof(WorldCoords.latlon_to_world(51.515, 0.50), 30.0, 3, 99)
	print("[civil-def] camouflage roof -> %d meshes over a size-3 works" % _count_meshes(camp))
	camp.free()
	print("[civil-def] kinds: %s" % [kinds])
	print("[civil-def] %d/%d civil-defence sites built >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[civil-def] %d civil-defence sites registered" % WorldPopulator.instance.civil_defence_sites)
	get_tree().quit()


## Debug (--aviation-test): the P16 aviation support. Builds every site from data/aviation_support_1940.json -
## AviationSupportKit scenery (seaplane / flying-boat bases, airship stations, kite-balloon sites) - and prints
## the mesh counts and the kinds covered. Engine-free smoke test.
func _aviation_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/aviation_support_1940.json", FileAccess.READ)
	if f == null:
		print("[aviation] data/aviation_support_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[aviation] aviation_support_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "seaplane_base"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = AviationSupportKit.build(kind, pos, float(r.get("heading_deg", 0.0)), int(r.get("size", 1)), hash(id))
		var m: int = _count_meshes(n)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[aviation] %-26s %-16s size %d at (%.0f, %.0f) -> %3d meshes" % [id, kind, int(r.get("size", 1)), pos.x, pos.z, m])
		n.free()
	print("[aviation] kinds: %s" % [kinds])
	print("[aviation] %d/%d aviation-support sites built >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[aviation] %d aviation-support sites registered" % WorldPopulator.instance.aviation_support_sites)
	get_tree().quit()


## Debug (--forestry-test): the P17 forestry. Builds every site from data/forestry_1940.json - ForestryKit
## scenery (Forestry Commission plantations and wartime timber camps) - and prints the mesh counts and kinds.
func _forestry_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/forestry_1940.json", FileAccess.READ)
	if f == null:
		print("[forestry] data/forestry_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[forestry] forestry_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "plantation"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = ForestryKit.build(kind, pos, float(r.get("heading_deg", 0.0)), int(r.get("size", 1)), hash(id))
		var m: int = _count_meshes(n)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[forestry] %-24s %-12s size %d at (%.0f, %.0f) -> %3d meshes" % [id, kind, int(r.get("size", 1)), pos.x, pos.z, m])
		n.free()
	print("[forestry] kinds: %s" % [kinds])
	print("[forestry] %d/%d forestry sites built >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[forestry] %d forestry sites registered" % WorldPopulator.instance.forestry_sites)
	get_tree().quit()


## Debug (--navigation-aid-test): the P18 navigation aids. Builds every site from data/navigation_aids_1940.json -
## NavigationAidKit scenery (radio beacons, DF stations, beacon masts, approach lighting) - and prints the kinds.
func _navigation_aid_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/navigation_aids_1940.json", FileAccess.READ)
	if f == null:
		print("[nav-aid] data/navigation_aids_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[nav-aid] navigation_aids_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "radio_beacon"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = NavigationAidKit.build(kind, pos, float(r.get("heading_deg", 0.0)), int(r.get("size", 1)), hash(id))
		var m: int = _count_meshes(n)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[nav-aid] %-22s %-14s size %d at (%.0f, %.0f) -> %3d meshes" % [id, kind, int(r.get("size", 1)), pos.x, pos.z, m])
		n.free()
	print("[nav-aid] kinds: %s" % [kinds])
	print("[nav-aid] %d/%d navigation-aid sites built >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[nav-aid] %d navigation-aid sites registered" % WorldPopulator.instance.navigation_aid_sites)
	get_tree().quit()


## Debug (--military-depth-test): the P19 military depth. Builds every site from data/military_depth_1940.json -
## MilitaryDepthKit scenery (transit camps, ammo depots, vehicle parks, horse columns, tank trains) - and prints
## the mesh counts and kinds. Engine-free smoke test.
func _military_depth_test() -> void:
	var f: FileAccess = FileAccess.open("res://data/military_depth_1940.json", FileAccess.READ)
	if f == null:
		print("[mil-depth] data/military_depth_1940.json missing")
		get_tree().quit()
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (d is Dictionary):
		print("[mil-depth] military_depth_1940.json did not parse")
		get_tree().quit()
		return
	var sites: Array = (d as Dictionary).get("sites", [])
	var kinds: Dictionary = {}
	var ok: int = 0
	var fails: Array = []
	for e in sites:
		var r: Dictionary = e
		var id: String = str(r.get("id", "?"))
		var kind: String = str(r.get("kind", "transit_camp"))
		var pos: Vector3 = WorldCoords.latlon_to_world(float(r["lat"]), float(r["lon"]))
		var n: Node3D = MilitaryDepthKit.build(kind, pos, float(r.get("heading_deg", 0.0)), int(r.get("size", 1)), hash(id))
		var m: int = _count_meshes(n)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if m >= 1:
			ok += 1
		else:
			fails.append(id)
		print("[mil-depth] %-24s %-16s size %d at (%.0f, %.0f) -> %3d meshes" % [id, kind, int(r.get("size", 1)), pos.x, pos.z, m])
		n.free()
	print("[mil-depth] kinds: %s" % [kinds])
	print("[mil-depth] %d/%d military-depth sites built >= 1 mesh (%s)" % [ok, sites.size(), "all ok" if fails.is_empty() else ", ".join(PackedStringArray(fails))])
	if WorldPopulator.instance != null:
		print("[mil-depth] %d military-depth sites registered" % WorldPopulator.instance.military_depth_sites)
	get_tree().quit()


func _count_instances_named(n: Node, nm: String) -> int:
	var c: int = 0
	for ch in n.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMeshInstance3D = ch
		if mm.multimesh != null and String(mm.name) == nm:
			c += mm.multimesh.instance_count
	return c


func _count_emitters(n: Node) -> int:
	var c: int = 0
	for ch in n.find_children("*", "", true, false):
		if ch is ChimneySmokes:
			c += (ch as ChimneySmokes).points.size()
	return c


func _count_meshes(n: Node) -> int:
	var c: int = 0
	for ch in n.find_children("*", "MeshInstance3D", true, false):
		c += 1
	return c


func _count_ships(n: Node) -> int:
	var c: int = 0
	for ch in n.find_children("*", "", true, false):
		if ch is GroundShip:
			c += 1
	return c


## Debug (--campaign-test): play a campaign headlessly (random results), print the situation, and build the menu once.
func _campaign_test() -> void:
	Campaign.new_campaign("Allies", "spitfire", "biggin_hill", "1944-06-01")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		var offers: Array = Campaign.state["offers"]
		var k: int = rng.randi() % offers.size()
		var cfg: Dictionary = Campaign.offer_config(k)
		var ok: bool = rng.randf() < 0.65
		var r: Dictionary = Campaign.record_result(ok, {"score": 400, "kills": rng.randi() % 3, "reason": "" if ok else "player killed"}, cfg)
		print("[campaign] day %d  %s  %s -> own str %d ind %d | enemy str %d ind %d  %s" % [int(Campaign.state["day"]), String(offers[k]["kind"]), "OK" if ok else "FAIL",
			int(Campaign.state["strength"]["own"]), int(Campaign.state["industry"]["own"]), int(Campaign.state["strength"]["enemy"]), int(Campaign.state["industry"]["enemy"]), str(r.get("campaign", ""))])
		if str(Campaign.state["ended"]) != "":
			break
	print("[campaign] offers now: ", (Campaign.state["offers"] as Array).map(func(o: Dictionary) -> String: return String(o["title"])))
	print("[campaign] cfg: ", Campaign.offer_config(0))
	var cm := CampaignMenu.new()
	add_child(cm)
	await get_tree().process_frame
	print("[campaign] menu built ok, children=", cm.get_child_count())
	Campaign.delete_save()
	get_tree().quit()


## Debug (--planner-test): drive the flight planner without a mouse and print the plans it produces.
func _planner_test() -> void:
	var fp := FlightPlanner.new()
	fp.side = "Allies"
	add_child(fp)
	await get_tree().process_frame
	var cases: Array = [["eindhoven", 0, 0], ["", 1, 1], ["", 1, 2], ["", 1, 3], ["", 1, 4], ["", 1, 5]]
	for c in cases:
		fp._on_picked(51.45, 5.37, str(c[0]))
		fp._start_type.select(int(c[1]))
		fp._scenario.select(int(c[2]))
		fp.confirmed.connect(func(plan: Dictionary) -> void: print("[planner] ", plan), CONNECT_ONE_SHOT)
		fp._on_fly()
	get_tree().quit()


func _initial_config() -> Dictionary:
	if Engine.has_meta(MENU_META):
		Engine.remove_meta(MENU_META)
		if Engine.has_meta(CFG_META):
			Engine.remove_meta(CFG_META)
		return {}
	if Engine.has_meta(CFG_META):
		return Engine.get_meta(CFG_META) as Dictionary
	var skip: bool = _args.has("--skip-menu")
	for a in _args:
		if a.begins_with("--mode=") or a.begins_with("--shot=") or a.begins_with("--tour=") or a.begins_with("--dam-day=") or a.begins_with("--pow-op=") or a.begins_with("--air-op="):
			skip = true
	if not skip:
		return {}
	for a in _args:       # debug: start a Dam Busters course day directly (--dam-day=N, 0-based)
		if a.begins_with("--dam-day="):
			return DamCampaign.config_for(int(a.substr(10)))
	for a in _args:       # debug: start a POW escape operation directly (--pow-op=N, 0-based)
		if a.begins_with("--pow-op="):
			return PowEscapeCampaign.config_for(int(a.substr(9)))
	for a in _args:       # debug: start a D-Day airborne operation directly (--air-op=N, 0-based)
		if a.begins_with("--air-op="):
			return AirborneCampaign.config_for(int(a.substr(9)))
	var cfg: Dictionary = {"side": "Allies", "aircraft": "", "mode": "free", "difficulty": 0.5, "weather": "clear", "time": "noon", "ambient": false}
	for a in _args:
		if a.begins_with("--mode="):
			cfg["mode"] = a.substr(7)
		elif a.begins_with("--side="):
			cfg["side"] = "Axis" if a.substr(7).to_lower() == "axis" else "Allies"
		elif a.begins_with("--aircraft="):
			cfg["aircraft"] = a.substr(11)
		elif a.begins_with("--difficulty="):
			var v: String = a.substr(13).to_lower()
			cfg["difficulty"] = {"easy": 0.2, "normal": 0.5, "hard": 0.85}.get(v, float(v) if v.is_valid_float() else 0.5)
		elif a.begins_with("--weather="):
			cfg["weather"] = a.substr(10)
		elif a.begins_with("--time="):
			cfg["time"] = a.substr(7)
		elif a == "--ambient":
			cfg["ambient"] = true
		elif a.begins_with("--spawn="):
			cfg["spawn"] = a.substr(8)
		elif a.begins_with("--wingmen="):
			cfg["wingmen"] = int(a.substr(10))
		elif a.begins_with("--plan="):   # debug: lat,lon,airfield_id|-,airborne(0/1),alt_m,heading  (planner spawn without the UI)
			var pf: PackedStringArray = a.substr(7).split(",")
			cfg["spawn_lat"] = float(pf[0])
			cfg["spawn_lon"] = float(pf[1])
			cfg["spawn_airfield"] = "" if pf[2] == "-" else pf[2]
			cfg["spawn_airborne"] = pf[3] == "1"
			cfg["spawn_alt"] = float(pf[4])
			cfg["spawn_heading"] = float(pf[5])
		elif a.begins_with("--planes="):
			cfg["planes"] = int(a.substr(9))
		elif a.begins_with("--wave="):
			cfg["start_wave"] = int(a.substr(7))
	if String(cfg["aircraft"]) == "" and String(cfg["mode"]) != "historical":     # historical: start_game picks the mission's own aircraft
		cfg["aircraft"] = AircraftCatalog.default_fighter(cfg["side"])
	return cfg


func _mission_audit() -> void:
	var pop: WorldPopulator = WorldPopulator.ensure(self)
	var bad: int = 0
	var checked: int = 0
	for m in HistoricalMissions.list():
		var mid: String = str((m as Dictionary).get("id", "?"))
		for sd in (m as Dictionary).get("sides", []):
			var sname: String = str(sd["side"])
			var af: String = str(sd.get("start_airfield", ""))
			if af != "" and pop.get_airfield(af) == null:
				print("[audit] %s/%s: start airfield '%s' does not resolve" % [mid, sname, af])
				bad += 1
			if sd.has("aircraft") and (sd["aircraft"] as Array).is_empty():
				print("[audit] %s/%s: no aircraft listed" % [mid, sname])
				bad += 1
			for aid in sd.get("aircraft", []):
				if not AircraftCatalog.ids_for_side(sname).has(str(aid)):
					print("[audit] %s/%s: aircraft '%s' is not a %s aircraft" % [mid, sname, str(aid), sname])
					bad += 1
		var role_by: Dictionary = (m as Dictionary).get("roles", {})
		for sname in ["Allies", "Axis"]:
			var ids: Array = ((m as Dictionary).get("objectives", {}) as Dictionary).get(sname, [])
			if (m as Dictionary).get("sides", []).filter(func(x: Variant) -> bool: return str(x["side"]) == sname).is_empty():
				continue
			if ids.is_empty() and str(role_by.get(sname, "strike")) in ["strike", "strafe", "escort"]:
				print("[audit] %s/%s: role %s but no objectives" % [mid, sname, str(role_by.get(sname, "strike"))])
				bad += 1
			for id in ids:
				checked += 1
				if pop.get_target_info(str(id)).is_empty():
					print("[audit] %s/%s: objective '%s' has no target info" % [mid, sname, str(id)])
					bad += 1
					continue
				var n: Node = pop.spawn_target(str(id))
				if n == null or not n.has_signal("destroyed"):
					print("[audit] %s/%s: objective '%s' did not spawn a destroyable target" % [mid, sname, str(id)])
					bad += 1
	print("[audit] %d missions, %d objectives checked, %d problems" % [HistoricalMissions.list().size(), checked, bad])
	get_tree().quit()


func _ui_shot() -> void:
	# debug: --ui-shot=path saves a screenshot 1.5 s (real time) after the first UI overlay appears, then quits
	for a in _args:
		if a.begins_with("--ui-shot="):
			var path: String = a.substr(10)
			var shot_delay: float = 5.0
			for da in _args:
				if da.begins_with("--shot-delay="):
					shot_delay = float(da.substr(13))
			get_tree().create_timer(shot_delay, true, false, true).timeout.connect(func() -> void:
				# the image must be taken after a frame has been drawn: grabbing it straight from a timer
				# callback returns an empty (black) texture
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(path)
				get_tree().quit())


func _show_menu() -> void:
	in_game = false
	_ui_shot()
	# screenshot hook: WW2_SETTINGS_PAGE=<video|render|audio|music|gameplay|controls> opens Settings straight
	# on that page so a capture run can reach it (settings_menu.gd reads the same env var)
	if OS.get_environment("WW2_SETTINGS_PAGE") != "":
		_debug_open_options()
	_menu_anchor = Node3D.new()
	_menu_anchor.name = "MenuAnchor"
	add_child(_menu_anchor)
	_menu_cam = Camera3D.new()
	_menu_cam.far = 48000.0
	_menu_cam.fov = 60.0
	_menu_anchor.add_child(_menu_cam)
	_menu_cam.make_current()
	terrain.set_focus(_menu_anchor)
	water.focus = _menu_anchor
	TimeOfDay.set_preset("noon")
	WeatherManager.set_weather("clear", 0.1)
	_update_menu_cam(0.0)
	# the start menu (and its music) is only built once the warning / licence screens have been dealt with
	if _legal_gate_needed():
		await _run_legal_gate()
	if _intro_start() >= 0.0:
		await _run_intro(_intro_start())
	_menu = (load(MENU_SCENE) as PackedScene).instantiate() as StartMenu
	add_child(_menu)
	_menu.start_requested.connect(start_game)
	_menu.quit_requested.connect(func() -> void: get_tree().quit())
	for fa in _args:
		if fa.begins_with("--film="):    # debug: --film=<chapter>[,<seconds>] opens the training film on that frame
			var fp: PackedStringArray = fa.substr(7).split(",")
			_menu.call_deferred("open_film", int(fp[0]), float(fp[1]) if fp.size() > 1 else 0.0)
	if _args.has("--menu-test"):    # debug: pick missions in the start menu and print the side / aircraft it selects
		_menu_test.call_deferred()


## Photosensitivity warning once per launch (not again when returning to the menu in the same session), licence
## agreement only until it has been accepted, optional DLSS download offer. Skipped in headless / automated runs.
func _legal_gate_needed() -> bool:
	if DisplayServer.get_name() == "headless" or _args.has("--menu-test") or _args.has("--skip-legal"):
		return false
	return not LegalGate.session_done


## Opening cinematic once per launch (before the menu). --intro=<seconds> forces it from that point (debug);
## --skip-intro / --skip-legal / headless runs never show it. Returns -1 for "do not play".
var _intro_running: bool = false


func _intro_start() -> float:
	for a in _args:
		if a.begins_with("--intro="):
			return float(a.substr(8))
	if DisplayServer.get_name() == "headless" or _args.has("--menu-test") or _args.has("--skip-legal") or _args.has("--skip-intro"):
		return -1.0
	return -1.0 if IntroCutscene.shown else 0.0


func _run_intro(start_at: float) -> void:
	IntroCutscene.shown = true
	_intro_running = true
	var intro := IntroCutscene.new()
	add_child(intro)
	intro.freeze = _args.has("--intro-freeze")
	intro.play(_menu_cam, _menu_anchor, start_at)
	await intro.finished
	_intro_running = false
	TimeOfDay.set_preset("noon")
	WeatherManager.set_weather("clear", 0.1)
	_update_menu_cam(0.0)


func _run_legal_gate() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var gate := LegalGate.new()
	layer.add_child(gate)
	await gate.done
	LegalGate.session_done = true
	layer.queue_free()


func _update_menu_cam(delta: float) -> void:
	if _intro_running:
		return
	_menu_t += delta * 0.06
	var c: Vector3 = WorldCoords.latlon_to_world(51.13, 1.31)
	var p: Vector3 = c + Vector3(cos(_menu_t), 0.0, sin(_menu_t)) * 3200.0
	p.y = 1400.0
	_menu_anchor.global_position = p
	_menu_cam.look_at(Vector3(c.x, 150.0, c.z), Vector3.UP)


# ---------------------------------------------------------------- session

var _last_wait_log: int = -1


func start_game(cfg: Dictionary) -> void:
	GroundKit.lp("start_game begin")
	_reset_sim_warp()      # every sortie starts at 1x: a warp never carries in from the menu, a replay or the results screen
	config = cfg.duplicate()
	Engine.set_meta(CFG_META, config)
	if _menu:
		_menu.queue_free()
		_menu = null
	if _menu_anchor:
		_menu_anchor.queue_free()
		_menu_anchor = null
	if String(config.get("mode", "")) == "historical":     # side / aircraft must fit the mission (menu, debug args, campaign)
		for a in _args:
			if a.begins_with("--mission=") and String(config.get("mission", "")) == "":
				config["mission"] = a.substr(10)
		var msides: Array = HistoricalMissions.sides_of(String(config.get("mission", "")))
		if not msides.is_empty() and not msides.has(String(config.get("side", "Allies"))):
			config["side"] = msides[0]
			config["aircraft"] = ""
		if String(config.get("aircraft", "")) == "":
			var mm: Dictionary = HistoricalMissions.get_mission(String(config.get("mission", "")))
			for sd in mm.get("sides", []):
				if str(sd["side"]) == String(config.get("side", "Allies")):
					for aid in sd.get("aircraft", []):
						if AircraftCatalog.ids_for_side(String(config["side"])).has(str(aid)):
							config["aircraft"] = str(aid)
							break
	var side: String = String(config.get("side", "Allies"))
	GameState.player_side = side
	GameState.era_date = String(config.get("era_date", ""))
	for a in _args:
		if a.begins_with("--date="):   # debug: force the war date (YYYY-MM-DD) for screenshots / perf runs
			GameState.era_date = a.substr(7)
	if WorldPopulator.instance != null and is_instance_valid(WorldPopulator.instance):
		WorldPopulator.instance.on_era_date(GameState.era_date)
	else:
		EraClock.set_date(GameState.era_date)
	# Quick missions start from a random friendly airfield each sortie (historical / training missions pick
	# their own field, and the planner overrides this later). Previously it was always the first one (Manston).
	var side_fields: Array = SIDE_AIRFIELDS.get(side, [])
	var mode_id: String = String(config.get("mode", ""))
	if not side_fields.is_empty():
		if mode_id == "historical" or mode_id == "training":
			if not side_fields.has(GameState.start_airfield):
				GameState.start_airfield = String(side_fields[0])
		else:
			GameState.start_airfield = String(side_fields[randi() % side_fields.size()])
	GameState.spawn_point = {}
	var sp: Dictionary = SpawnPoints.find(String(config.get("spawn", "")))
	if not sp.is_empty():
		if sp.has("airfield"):
			GameState.start_airfield = String(sp["airfield"])
		else:
			GameState.spawn_point = sp
	_apply_planned_spawn()
	var aid: String = String(config.get("aircraft", ""))
	if aid == "":
		aid = AircraftCatalog.default_fighter(side)

	var packed: PackedScene = load(AIRCRAFT_SCENE)
	player = packed.instantiate() as Aircraft
	player.name = "Player"
	player.stats = AircraftCatalog.load_stats(aid)
	player.team = side
	player.player_controlled = true
	add_child(player)
	if AircraftCatalog.is_bomber(aid):
		CrewIntercom.attach(player)
	player.crashed.connect(_on_player_crashed)
	player.landed.connect(func(_a: Aircraft) -> void: hud.show_message("Landed", 1.5))
	player.took_off.connect(func(_a: Aircraft) -> void: hud.show_message("Airborne", 1.5))

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.bind(player)

	hud = (load(HUD_SCENE) as PackedScene).instantiate() as HUD
	hud.visible = not _args.has("--nohud")      # debug: completely clean screenshots
	add_child(hud)
	hud.bind_aircraft(player)
	var gvis := GVision.new()
	gvis.hud = hud
	add_child(gvis)
	hud.bind_camera(camera_rig.chase_cam)
	camera_rig.view_changed.connect(func(_c: bool) -> void: hud.bind_camera(camera_rig.current_camera()))
	camera_rig.view_distance_changed.connect(func(msg: String, secs: float) -> void: hud.show_message(msg, secs))
	if _bail == null:
		_bail = BailOut.new()
		add_child(_bail)
		_bail.resolved.connect(_on_bail_resolved)
	_bail.setup(hud)
	turrets = null
	var old_sight: Node = get_node_or_null("Bombsight")
	if old_sight != null:
		remove_child(old_sight)
		old_sight.queue_free()
	# defensive guns: any bomber whose real fit includes turrets gets a gunner view (key L)
	if AircraftCatalog.is_bomber(player.stats.id) and not DefensiveTurrets.layout_for(player.stats.id, player.stats.bombs).is_empty():
		turrets = DefensiveTurrets.attach(player, hud, 0.45)
		if turrets != null:
			turrets.rig = camera_rig
	if player.stats.bombs >= 8:
		# heavy bombers additionally get the bombsight (N) + chart (M)
		player.bombsight_only = true
		var sight: Bombsight = Bombsight.attach(self, player, camera_rig, hud)
		sight.turrets = turrets
	else:
		# every other aircraft still gets the full-screen chart (M), without the bombsight
		var chart: Bombsight = Bombsight.attach(self, player, camera_rig, hud)
		chart.chart_only = true
		chart.turrets = turrets

	terrain.set_focus(player)
	water.focus = player
	var tcfg: String = String(config.get("time", "noon"))
	if tcfg.is_valid_float():
		TimeOfDay.set_time(float(tcfg))      # --time=17.6 (an hour) as well as the named presets
	else:
		TimeOfDay.set_preset(tcfg)
	WeatherManager.set_weather(String(config.get("weather", "clear")), 0.1)
	# moonlight for the mission date (planner or historical date): a full moon lights the night, a new moon hides bombers
	var mdate: String = String(config.get("mission_date", GameState.era_date))
	TimeOfDay.set_moon_illum(MoonWeather.illumination(mdate) if mdate != "" else 1.0)

	var mid: String = String(config.get("mode", "free"))
	# moving weather fronts in the open modes; scripted / training sorties keep the weather they were set with
	WeatherManager.fronts_enabled = not (mid in ["training", "dambuster", "historical", "pow_escape", "airborne"]) and not _args.has("--no-fronts")
	if _args.has("--front-now"):      # debug: a front from the west-south-west, close by (look along 250 to see it)
		WeatherManager.wind_dir_deg = 250.0
		WeatherManager._wind_target_dir = 250.0
	if WeatherManager.fronts_enabled and (_args.has("--front-now") or randf() < 0.5):
		WeatherManager.spawn_front(240.0 if _args.has("--front-now") else -1.0)
	mode = ModeRegistry.create(mid)
	if mode == null:
		push_warning("Unknown or missing mode '%s', using free flight" % mid)
		mode = ModeRegistry.create("free")
	mode.name = "Mode"
	mode.set_meta("mode_id", mid)
	mode.setup(self, player, hud)
	if mode.has_method("configure"):
		mode.call("configure", config)
	if config.has("wingmen"):
		mode.wingmen_wanted = int(config["wingmen"])
	add_child(mode)
	mode.mission_complete.connect(_on_mission_complete)
	# the war going on around you: distant flak, searchlights, raids on towns, the V-weapons blitz (scenery only)
	if not (mid in ["dambuster", "training", "pow_escape", "airborne"]) and not _args.has("--no-skywar"):
		add_child(SkyWar.new().setup(self, player, hud, mid))

	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.stats_provider = func() -> Dictionary: return mode.call("live_stats") if is_instance_valid(mode) and mode.has_method("live_stats") else {}
	_pause.restart_requested.connect(restart)
	_pause.menu_requested.connect(quit_to_menu)
	_pause.show_end_sortie = bool(config.get("career", false))
	_pause.end_sortie_requested.connect(_end_career_sortie)
	_pause.quit_requested.connect(func() -> void: get_tree().quit())
	_pause.warp_requested.connect(func(mult: int) -> void: _set_sim_warp(mult))
	_pause.warp_reset = _reset_sim_warp      # a warp never survives a pause (the menu row picks a new one)

	in_game = true
	_spawn_player()
	# Load-in: menu painting, no sound and a frozen aircraft while the scenery around the start streams in.
	var cover := CanvasLayer.new()
	cover.layer = 128
	var black := Control.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(black)
	var load_bar: ProgressBar = _build_load_screen(black)
	Radio.reset_channel()
	_play_briefing()
	add_child(cover)
	AudioManager.set_game_sound_muted(true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var pop: Node = null
	for c in get_children():
		if c is WorldPopulator:
			pop = c
	if pop != null:
		pop.set("boost", true)
		pop.set("pending", 999)
	var waited: float = 0.0
	var _load_t0: int = Time.get_ticks_msec()
	var peak: float = 1.0
	var min_wait: float = REPLAY_LOAD_SECONDS if _loaded_once else LOAD_SCREEN_SECONDS
	# Build every aircraft type ahead, one per frame behind the loading screen, so none has to be built (a 70-250 ms
	# hitch) when it first appears in flight; the player's own type and the enemy's come first.
	var warm: Array = []
	for wi0 in AircraftModels.warm_list(String(player.stats.id) if player != null and player.stats != null else "", GameState.player_side):
		warm.append(Callable(AircraftModels, "prototype").bind(String(wi0[0]), String(wi0[1])))
	# ... then the parked-aircraft meshes and the airfield / camp props, so flying up to an airfield builds nothing new
	warm.append_array(ParkedAircraft.warm_jobs())
	warm.append_array(AirfieldAssets.warm_jobs())
	while waited < min_wait or (((pop != null and int(pop.get("pending")) > 0) or not terrain.is_settled()) and waited < 120.0):
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not warm.is_empty() and waited > 0.5:
			var wt0: int = Time.get_ticks_usec()
			while not warm.is_empty() and Time.get_ticks_usec() - wt0 < 30000:     # ~30 ms of warming a frame
				(warm.pop_front() as Callable).call()
		if int(waited) != _last_wait_log:
			_last_wait_log = int(waited)
			if _last_wait_log % 3 == 0:
				print("[load] %d s: pending=%d terrain_settled=%s terrain_pending=%d inflight=%d" % [_last_wait_log, int(pop.get("pending")) if pop != null else 0, terrain.is_settled(), terrain.get("_pending").size() if terrain.get("_pending") != null else -1, int(terrain.get("_inflight"))])
		var pend: float = float(int(pop.get("pending"))) if pop != null else 0.0
		if pend < 900.0:
			peak = maxf(peak, pend)
		var stream_k: float = 1.0 - clampf(pend / peak, 0.0, 1.0) if pend < 900.0 else 0.0
		var k: float = minf(waited / min_wait, 1.0) * 0.4 + stream_k * 0.6
		load_bar.value = maxf(load_bar.value, k * (1.0 if terrain.is_settled() else 0.9))
	load_bar.value = 1.0
	# whatever is still unbuilt is finished now, still behind the loading screen (never in flight)
	for wj in warm:
		(wj as Callable).call()
	print("[load] scenery ready after %.1f s (pending %d), wall %.1f s" % [waited, int(pop.get("pending")) if pop != null else 0, float(Time.get_ticks_msec() - _load_t0) / 1000.0])
	if pop != null:
		pop.set("boost", false)
	for _i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.3 if _loaded_once else 1.0).timeout
	_loaded_once = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	AudioManager.set_game_sound_muted(false)
	var tw := create_tween()
	tw.tween_property(black, "modulate:a", 0.0, 0.6)
	tw.tween_callback(cover.queue_free)
	mode.start()
	add_child(GameMusic.new())       # occasional in-flight music (fades in after a while)
	_parse_debug_args()


## Loading screen: a menu painting (slow pan), the sortie name and a streaming progress bar. Returns the bar.
func _build_load_screen(root: Control) -> ProgressBar:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var art := MenuBackground.new()
	art.animate = false      # loading screen: the painting stays still
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(art)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;
void fragment(){ COLOR = vec4(0.02, 0.02, 0.015, smoothstep(0.62, 1.0, UV.y) * 0.85); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	shade.material = sm
	root.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 56.0
	box.offset_right = -56.0
	box.offset_top = -150.0
	box.offset_bottom = -44.0
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	var mode_id: String = String(config.get("mode", "free"))
	var st: AircraftStats = AircraftCatalog.load_stats(String(config.get("aircraft", "")))
	var head := UIKit.label("PREPARING SORTIE", 15, UIKit.RED, true)
	box.add_child(head)
	var title := UIKit.label(ModeRegistry.display_name(mode_id).to_upper() if ModeRegistry.MODES.has(mode_id) else "CHANNEL AIR WAR", 40, UIKit.TEXT, true)
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	if st != null:
		box.add_child(UIKit.label("%s  ·  %s" % [st.display_name, String(config.get("side", "Allies"))], 18, UIKit.ACCENT))
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(1, 1, 1, 0.12)
	var bf := StyleBoxFlat.new()
	bf.bg_color = UIKit.ACCENT
	bar.add_theme_stylebox_override("background", bb)
	bar.add_theme_stylebox_override("fill", bf)
	box.add_child(bar)
	for a in _args:
		if a.begins_with("--load-shot="):   # debug: capture the loading screen
			var path: String = a.substr(12)
			get_tree().create_timer(2.5).timeout.connect(func() -> void: get_viewport().get_texture().get_image().save_png(path))
	return bar


## Spoken briefing over the loading screen (keeps playing into the start of the sortie; radio calls wait for it).
func _play_briefing() -> void:
	var side: String = "axis" if String(config.get("side", "Allies")) == "Axis" else "allies"
	var mode_id: String = String(config.get("mode", "free"))
	if mode_id == "historical":
		var mid: String = String(config.get("mission", ""))
		if not Radio.narrate("brief/%s_%s" % [mid, side]):   # no mission-specific briefing: generic one for the role
			var m: Dictionary = HistoricalMissions.get_mission(mid)
			var role: String = str((m.get("roles", {}) as Dictionary).get(String(config.get("side", "Allies")), "strike"))
			Radio.narrate("brief/generic_%s_%s" % [{"escort": "strike", "sweep": "defend"}.get(role, role), side])
	elif mode_id in ["dogfight", "bombing", "ground"]:
		var base: String = "brief/mode_%s_%s" % [mode_id, side]
		var v: int = randi_range(1, 3)   # variety: variant 1 is the base file, 2 and 3 are the other briefings
		if v == 1 or not Radio.narrate("%s_%d" % [base, v]):
			Radio.narrate(base)
	elif mode_id == "dambuster":
		var di: int = clampi(int(config.get("day", 0)), 0, DamCampaign.count() - 1)
		Radio.narrate("brief/dam_%s_%s" % [DamCampaign.DAYS[di]["id"], side])


func restart() -> void:
	_reset_sim_warp()
	Radio.reset_channel()
	get_tree().paused = false
	GameState.paused = false
	Engine.set_meta(CFG_META, config)
	get_tree().reload_current_scene()


func quit_to_menu() -> void:
	if _bail != null:
		_bail.cancel()
	_reset_sim_warp()
	Radio.reset_channel()
	get_tree().paused = false
	GameState.paused = false
	if Engine.has_meta(CFG_META):
		Engine.remove_meta(CFG_META)
	Engine.set_meta(MENU_META, true)
	if bool(config.get("campaign", false)):
		Engine.set_meta("open_campaign", true)
	if bool(config.get("career", false)):
		Engine.set_meta("open_career", true)
	get_tree().reload_current_scene()


func _on_mission_complete(success: bool, stats: Dictionary) -> void:
	_reset_sim_warp()
	if _pause:
		_pause.enabled = false
	if success and String(config.get("mode", "")) == "historical":
		GameState.mark_mission_done(String(config.get("mission", "")))
	if bool(config.get("campaign", false)):
		stats = stats.duplicate()
		stats.merge(Campaign.record_result(success, stats, config), true)
	if bool(config.get("career", false)):
		if _bail != null:
			_bail.cancel()
		stats = stats.duplicate()
		stats.merge(Career.record_result(success, stats, config), true)
	if String(config.get("mode", "")) == "dambuster":
		DamCampaign.record(int(config.get("day", 0)), success)
	if String(config.get("mode", "")) == "airborne":
		AirborneCampaign.record(int(config.get("op", 0)), success)
	if String(config.get("mode", "")) == "pow_escape":
		PowEscapeCampaign.record(int(config.get("op", 0)), success)
	_results = ResultsScreen.show_results(self, success, stats)
	MedalCeremony.show_pending(self, GameState.player_side)     # any decoration earned is presented over the results
	_ui_shot()
	_results.restart_requested.connect(restart)
	_results.menu_requested.connect(quit_to_menu)
	_results.quit_requested.connect(func() -> void: get_tree().quit())


func _mode_airborne() -> bool:
	if config.has("spawn_airborne"):
		return bool(config["spawn_airborne"])
	if mode:
		var v: Variant = mode.get("start_airborne")
		if v != null:
			return bool(v)
	return GameState.start_airborne


func _manages_respawn() -> bool:
	if mode:
		var v: Variant = mode.get("manages_respawn")
		return v != null and bool(v)
	return false


## (Re)place the player at the current airfield. Public: modes may call `world.respawn_player()`.
func respawn_player() -> void:
	if _bail != null and _bail.active:
		_bail.pending_respawn = true     # the pilot is still on his parachute: respawn once he is down
		return
	_spawn_player()


## Respawn after a life was used, bringing in replacement wingmen: the flight grows each time you go down.
func _respawn_player_with_support() -> void:
	if _bail != null and _bail.active:
		_bail.pending_respawn = true
		return
	if mode != null and is_instance_valid(mode) and mode.has_method("reinforce_wingmen"):
		mode.call("reinforce_wingmen", 2)
	_spawn_player()


## Bomber gunner view: L steps through the defensive gun positions (the aircraft flies itself while gunning).
func _unhandled_input(event: InputEvent) -> void:
	# F12 = photo: the HUD is hidden for a moment and a clean screenshot is saved to Pictures.
	if in_game and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F12:
		get_viewport().set_input_as_handled()
		_take_photo()
		return
	if not in_game or event.is_echo() or not event.is_action_pressed("gunner_view"):
		return
	get_viewport().set_input_as_handled()
	if turrets == null or not is_instance_valid(turrets) or turrets.turret_count() == 0:
		return
	var bs: Node = get_node_or_null("Bombsight")
	if bs != null:
		if bool(bs.get("active")):
			bs.call("set_active", false)
		if bool(bs.get("map_open")):
			bs.call("set_map", false)
	turrets.cycle_view()


## Spawn chosen on the planner map: an airfield (runway or airborne over it) or a free point in the air.
func _apply_planned_spawn() -> void:
	if not config.has("spawn_lat"):
		return
	var af_id: String = String(config.get("spawn_airfield", ""))
	GameState.spawn_point = {}
	if af_id != "":
		if not airfields.has(af_id):
			var af: Airfield = WorldPopulator.ensure(self).get_airfield(af_id)
			if af != null:
				airfields[af_id] = af
		if airfields.has(af_id):
			GameState.start_airfield = af_id
			return
	GameState.spawn_point = {"name": "Free spawn", "lat": float(config["spawn_lat"]), "lon": float(config["spawn_lon"]),
		"heading": float(config.get("spawn_heading", 90.0)), "alt": float(config.get("spawn_alt", 1200.0))}


func _spawn_report() -> void:
	if not _args.has("--spawn-debug") or player == null:
		return
	var ll: Vector2 = WorldCoords.world_to_latlon(player.global_position)
	var best: String = "-"
	var bd: float = 1.0e12
	for id in airfields.keys():
		var d: float = (airfields[id] as Node3D).global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = str(id)
	camera_rig.set_cockpit(_want_cockpit)   # re-apply now the rig has a pilot: at argument-parse time it
	# had no target, so the cockpit request went nowhere and the game stayed on the chase camera
	print("[spawn] %s: lat %.3f lon %.3f  alt %.0f m  %s  heading %03.0f  nearest field %s (%.1f km real)  side %s aircraft %s" % [String(config.get("mission", config.get("mode", ""))), ll.x, ll.y, player.global_position.y / 2.0, "ON GROUND" if player.on_ground else "airborne", player.get_heading_deg(), best, bd * WorldCoords.HORIZ_COMPRESSION / 1000.0, GameState.player_side, player.stats.id])


func _spawn_player() -> void:
	_spawn_player_inner()
	_spawn_report.call_deferred()


func _spawn_player_inner() -> void:
	player.player_controlled = true     # bail-out takes the controls away; a fresh spawn gives them back
	if _bail != null:
		_bail.cancel()
	var crew: Node = player.get_node_or_null("CrewIntercom") if player != null else null
	if crew != null:
		crew.call("reset_sortie")
	var af: Airfield = airfields[GameState.start_airfield]
	var heading: float = af.heading_deg
	var airborne: bool = _mode_airborne()
	if not GameState.spawn_point.is_empty():
		var sp: Dictionary = GameState.spawn_point
		var wp: Vector3 = WorldCoords.latlon_to_world(float(sp["lat"]), float(sp["lon"]))
		# highest ground in a 400 m square around the spawn, so a free start is never placed inside a hillside
		var gmax: float = 0.0
		for ox in [-400.0, 0.0, 400.0]:
			for oz in [-400.0, 0.0, 400.0]:
				gmax = maxf(gmax, terrain.get_height_at(wp + Vector3(ox, 0.0, oz)))
		wp.y = maxf(gmax, 0.0) + float(sp["alt"]) * WorldCoords.VERTICAL_SCALE
		player.reset_pose(wp, float(sp["heading"]), true)
		camera_rig.bind(player)
		terrain.set_focus(player)
		if hud and not _manages_respawn():
			hud.show_message(String(sp["name"]), 3.0)
		return
	if airborne:
		var pos: Vector3 = af.get_threshold_position()
		pos.y = af.surface_y + (float(config["spawn_alt"]) * WorldCoords.VERTICAL_SCALE if config.has("spawn_alt") else 650.0)
		if config.has("spawn_heading"):
			heading = float(config["spawn_heading"])
		player.reset_pose(pos, heading, true)
	else:
		var pos2: Vector3 = af.get_threshold_position()
		# room behind for the wingmen who take off after the player (ModeBase.runway_queue_length)
		if mode != null and is_instance_valid(mode) and mode.has_method("runway_queue_length"):
			pos2 += WorldCoords.heading_to_dir(heading) * minf(float(mode.call("runway_queue_length")), af.runway_length * 0.3)
		pos2.y = af.surface_y + player.stats.gear_height + 0.35
		player.reset_pose(pos2, heading, false)
		# the player's own ground crew, trolley-acc and chocks; they walk clear when the throttle opens
		if _send_off != null and is_instance_valid(_send_off):
			_send_off.queue_free()
		_send_off = null     # (the player's send-off ground crew was removed in v7.27)
	camera_rig.bind(player)
	terrain.set_focus(player)
	if hud and not _manages_respawn():
		hud.show_message("%s - %s" % [af.airfield_name, "airborne" if airborne else "hold Shift for throttle, S to rotate"], 4.0)


var _ceremony_t: float = 0.0


## A decoration earned in the air is presented once the aircraft is down and stopped.
func _check_ceremony(delta: float) -> void:
	_ceremony_t -= delta
	if _ceremony_t > 0.0:
		return
	_ceremony_t = 1.0
	if player == null or not is_instance_valid(player) or player.state != Aircraft.State.ALIVE:
		return
	if player.on_ground and player.speed < 2.0 and PilotLog.debug_run() == false:
		MedalCeremony.show_pending(self, GameState.player_side)


## Rearm: land at a friendly airfield and guns / bombs / rockets are restored.
func _check_rearm() -> void:
	if player == null or not is_instance_valid(player) or player.state != Aircraft.State.ALIVE:
		return
	if not player.on_ground:
		_rearmed = false
		return
	if _rearmed:
		return
	# touching down anywhere on a friendly field's runway (or inside the field, for its other runways) rearms
	var p: Vector3 = player.global_position
	for n in get_tree().get_nodes_in_group("airfield"):
		var af: Airfield = n as Airfield
		if af == null or not is_instance_valid(af) or af.team != player.team:
			continue
		var loc: Vector3 = af.global_transform.affine_inverse() * p
		var on_runway: bool = absf(loc.x) <= af.runway_width * 0.5 + 25.0 and absf(loc.z) <= af.runway_length * 0.5 + 40.0
		var in_field: bool = Vector2(loc.x, loc.z).length() <= af.runway_length * 0.6
		if not (on_runway or in_field):
			continue
		_rearmed = true
		var st: AircraftStats = player.stats
		var w: Variant = player.weapons
		var rockets: int = int(w.get("rockets_left")) if w != null else st.rockets
		var short: bool = player.ammo < st.ammo or player.bombs < st.bombs or rockets < st.rockets
		player.weapons.rearm()
		if short and hud and hud.has_method("show_message"):
			hud.call("show_message", "REARMED - guns, bombs and rockets restored", 3.0)
		break

func _on_player_crashed(a: Aircraft, reason: String) -> void:
	camera_rig.add_shake(1.0)
	if _bail != null and _bail.active:
		return     # bailing out: the fate is decided when the pilot is down (_on_bail_resolved)
	if bool(config.get("career", false)):
		_career_lost("sea" if reason == "ditched" else "crashed")
		return
	if _manages_respawn():
		return
	hud.show_message("CRASHED (%s) - respawning..." % reason, 3.0)
	_respawn_timer = 4.0
	if reason == "ditched":
		# down in the Channel: the airman's dinghy drifts at the splash point until a rescue flight finds him
		DitchRescue.start(self, a.global_position, hud)


## Safety net: if the player's aircraft is a dead wreck, nothing is queued to replace it, and no bail-out is in
## progress, start the respawn anyway - a missed crash signal must never leave the player stuck until restart.
var _dead_watch: float = 0.0


func _respawn_watchdog(delta: float) -> void:
	var stuck: bool = player != null and (not is_instance_valid(player) or player.state == Aircraft.State.DEAD) \
		and _respawn_timer < 0.0 and not (_bail != null and _bail.active) and not _manages_respawn() \
		and not bool(config.get("career", false)) and not GameState.paused
	if not stuck:
		_dead_watch = 0.0
		return
	_dead_watch += delta
	if _dead_watch > 7.0:
		_dead_watch = 0.0
		_respawn_timer = 0.5

## Pilot's Life: a free-flight sortie has no objective, so the pilot ends it himself once he is down.
func _end_career_sortie() -> void:
	if player == null or not is_instance_valid(player) or player.state != Aircraft.State.ALIVE:
		return
	if not player.on_ground:
		hud.show_message("Land before ending the sortie", 3.0)
		return
	if mode != null and is_instance_valid(mode) and mode.has_method("finish"):
		mode.call("finish", true, {"fate": "returned"})


## Pilot's Life: the pilot is lost (crash, or bailed out and down). The sortie ends with that fate; Career applies it.
func _career_lost(fate: String) -> void:
	if mode != null and is_instance_valid(mode) and mode.has_method("finish"):
		mode.call("finish", false, {"reason": "shot down", "fate": fate})


## The pilot is down (landed, or the descent skipped): the fate line, a dinghy and rescue flight at sea, then respawn.
const BAIL_COOL_OFF := 5.0       # seconds between the pilot landing and the replacement aircraft


func _on_bail_resolved(fate: String, pos: Vector3) -> void:
	var txt: String = BailOut.fate_text(fate, GameState.player_side)
	if hud != null and txt != "":
		hud.show_message(txt, 5.0)
	if bool(config.get("career", false)):
		_career_lost(fate)     # one life in a career: the sortie ends here
		return
	if fate == "sea":
		DitchRescue.start(self, pos, hud)
	# 5 s cool-off between landing (or skipping the descent) and being back in an aircraft
	if _bail.pending_respawn:
		_bail.pending_respawn = false
		_respawn_timer = BAIL_COOL_OFF
		if hud != null:
			hud.show_message("Back in the air in %d seconds..." % int(BAIL_COOL_OFF), BAIL_COOL_OFF)
	elif not _manages_respawn():
		_respawn_timer = BAIL_COOL_OFF
		if hud != null:
			hud.show_message("Back in the air in %d seconds..." % int(BAIL_COOL_OFF), BAIL_COOL_OFF)


# --- simulation time warp (] / [ in flight, F5 still steps the same ladder): the map is real-scale, so a
# multiplier on the whole simulation fast-forwards the long empty transits. This is Engine.time_scale, i.e. the
# flight model / AI / world all run faster, unlike GameState.time_speed which only speeds up the day/night clock
# (the two are independent). Capped at 32x by GameState.SIM_WARPS and cancelled the moment a hostile aircraft is
# anywhere near, so it can never be used to cheat a fight.
const WARP_CONTACT_RANGE := 5000.0    # hostile aircraft closer than this cancel the warp
var _warp_forced: bool = false        # debug (--warp=N): hold the warp for the whole run, ignoring the cancel
var _warp_log_t: float = 0.0          # ... and log the flight state once a second so a soak run can be read
var _tc_prev_key: bool = false        # F5 edge detector
var _tc_check: float = 0.0


## Debug (--warp=N) soak: once a second print the player's state, so a run can be checked for NaN / divergence.
func _log_warp_state(delta: float) -> void:
	_warp_log_t += delta / maxf(Engine.time_scale, 0.1)
	if _warp_log_t < 1.0:
		return
	_warp_log_t = 0.0
	var pl: Aircraft = player
	if pl == null or not is_instance_valid(pl):
		return
	print("[warp] %s  spd=%.1f eas=%.1f alt=%.1f agl=%.1f vs=%.1f g=%.2f aoa=%.1f stall=%.2f dt=%.1f ms  pos=%s" % [
		GameState.SIM_WARP_NAMES[GameState.sim_warp_index()], pl.speed, pl.eas, pl.get_altitude_m(), pl.altitude_agl,
		pl.velocity.y / 2.0, pl.g_load, rad_to_deg(pl._alpha_signed()), pl._stall_amount, delta * 1000.0, str(pl.global_position)])


## Push GameState.sim_warp into the engine. Call it after every change (or reset) of the warp.
func _apply_sim_warp() -> void:
	Engine.time_scale = float(GameState.sim_warp)


## Set the warp to `mult`, snapped down onto the SIM_WARPS ladder (so it can never exceed 32x), and apply it.
func _set_sim_warp(mult: int, note: String = "") -> void:
	GameState.snap_sim_warp(mult)
	_apply_sim_warp()
	if hud:
		hud.show_message(note if note != "" else ("TIME %s  (] / [ to change)" % GameState.SIM_WARP_NAMES[GameState.sim_warp_index()] if GameState.sim_warp > 1 else "Normal time"), 1.8)


## Back to real time (pause, results screen, restart, menu): the warp never survives out of a flight.
func _reset_sim_warp() -> void:
	GameState.reset_sim_warp()
	_apply_sim_warp()


## Warp keys plus the safety net: no warp while paused, on the ground, or with a hostile aircraft inside
## WARP_CONTACT_RANGE. Never compress time during combat.
func _update_sim_warp(delta: float) -> void:
	var pl: Aircraft = player as Aircraft
	var bailing: bool = _bail != null and _bail.active       # floating down on the parachute: warp allowed
	var can_warp: bool = bailing or (pl != null and pl.state == Aircraft.State.ALIVE and not pl.on_ground and not GameState.paused)
	if _warp_forced:
		_log_warp_state(delta)
		return
	if can_warp and Input.is_action_just_pressed("warp_up"):
		_set_sim_warp(GameState.step_sim_warp(1))
	elif can_warp and Input.is_action_just_pressed("warp_down"):
		_set_sim_warp(GameState.step_sim_warp(-1))
	var f5: bool = Input.is_key_pressed(KEY_F5)       # F5 cycles the same ladder (1x -> 2x -> ... -> 32x -> 1x)
	if f5 and not _tc_prev_key and can_warp:
		_set_sim_warp(GameState.step_sim_warp(1 if GameState.sim_warp_index() < GameState.SIM_WARPS.size() - 1 else -GameState.SIM_WARPS.size() + 1))
	_tc_prev_key = f5
	if GameState.sim_warp <= 1:
		return
	# delta is scaled by Engine.time_scale, so divide it back out: the sweep runs every half second of real time
	_tc_check -= delta / maxf(Engine.time_scale, 0.1)
	if _tc_check > 0.0:
		return
	_tc_check = 0.5
	if not can_warp:
		_set_sim_warp(1, "Normal time")
		return
	if bailing or pl == null or not is_instance_valid(pl):
		return          # on the parachute the warp is never cancelled by contact
	for n in get_tree().get_nodes_in_group("aircraft"):
		if n is Aircraft and (n as Aircraft).team != GameState.player_side and (n as Aircraft).state == Aircraft.State.ALIVE and (n as Node3D).global_position.distance_to(pl.global_position) < WARP_CONTACT_RANGE:
			_set_sim_warp(1, "Contact - normal time")
			return


var _perf_secs: float = 0.0
var _perf_settle: float = 10.0
var _perf_t: float = 0.0
var _perf_dt: PackedFloat32Array = []
var _perf_acc: Dictionary = {}


var _rail_speed: float = 0.0
var _rail_t: float = 0.0
var _rail_from: Vector3 = Vector3.ZERO
var _rail_dir: Vector3 = Vector3.FORWARD
var _rail_basis: Basis = Basis.IDENTITY


## Debug (--rail=SPEED): pin the player to a straight level line so every perf run sees the same frames.
func _rail_step(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_rail_t += delta
	player.global_transform = Transform3D(_rail_basis, _rail_from + _rail_dir * _rail_speed * _rail_t)
	player.velocity = _rail_dir * _rail_speed
	player.speed = _rail_speed


## Debug profiler (--perf=SECS[:SETTLE]): after SETTLE s in game, records every frame for SECS s and
## prints average / 1%-low FPS, CPU and GPU frame time, draw calls and object counts.
func _perf_step(delta: float) -> void:
	_perf_t += delta
	if _perf_t < _perf_settle:
		return
	var vp: RID = get_viewport().get_viewport_rid()
	_perf_dt.append(delta)
	var vals := {
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"rcpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"proc_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"prims_k": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
	for k in vals:
		_perf_acc[k] = float(_perf_acc.get(k, 0.0)) + float(vals[k])
	if _perf_t < _perf_settle + _perf_secs:
		return
	var n: int = _perf_dt.size()
	var sorted: Array = Array(_perf_dt)
	sorted.sort()
	var tot: float = 0.0
	for d in _perf_dt:
		tot += d
	var worst: float = 0.0
	var cnt: int = maxi(1, n / 100)
	for i in cnt:
		worst += float(sorted[n - 1 - i])
	var line := "PERF frames=%d avg_fps=%.1f low1_fps=%.1f" % [n, n / tot, cnt / worst]
	for k in _perf_acc:
		line += " %s=%.2f" % [k, float(_perf_acc[k]) / n]
	line += " aircraft=%d" % get_tree().get_nodes_in_group("aircraft").size()
	print(line)
	if _args.has("--perf-dump"):
		_perf_dump()
	_perf_secs = 0.0
	get_tree().quit()



## Debug: triangles (x instances) of visible geometry within 6 km of the camera, grouped by owner script / node name.
var _dump_r: float = 60000.0
func _perf_dump() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position
	var tally: Dictionary = {}
	var cnt: Dictionary = {}
	var shadow: Dictionary = {}
	var rev: Dictionary = {}
	for mk in Scatter._meshes:
		rev[Scatter._meshes[mk]] = str(mk)
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n
		if not g.is_visible_in_tree():
			continue
		var tris: float = 0.0
		var inst: int = 1
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			inst = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		if mesh == null:
			continue
		var ab: AABB = g.global_transform * g.get_aabb()
		var d: float = ab.get_center().distance_to(cp) - ab.size.length() * 0.5
		if d > _dump_r:
			continue
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end:
			continue
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si) if mesh is ArrayMesh else []
			if arr.is_empty():
				var fa: PackedVector3Array = mesh.get_faces()
				tris = fa.size() / 3.0
				break
			var idx = arr[Mesh.ARRAY_INDEX]
			var v = arr[Mesh.ARRAY_VERTEX]
			tris += (idx.size() if idx != null else (v.size() if v != null else 0)) / 3.0
		var owner_n: Node = g
		var key: String = ""
		while owner_n != null and key == "":
			var sc: Script = owner_n.get_script()
			if sc != null:
				key = sc.resource_path.get_file()
			owner_n = owner_n.get_parent()
		key += "/" + String(g.name).rstrip("0123456789@")
		var up: Node = g
		while up != null and up.get_parent() != null and not (up.get_parent().get_script() != null and up.get_parent().get_script().resource_path.ends_with("world_populator.gd")):
			up = up.get_parent()
		if up != null and up.get_parent() != null and up != g:
			key += " <" + String(up.name).rstrip("0123456789_-@").left(22) + ">"
			if String(up.name).begins_with("tile"):
				var par: Node = g.get_parent()
				key += " " + String(par.get_parent().name).rstrip("0123456789_-@").left(12) + ">" + String(par.name).rstrip("0123456789_-@").left(16) + "/" + str(mesh.resource_name if mesh.resource_name != "" else str(rev.get(mesh, "?"))).left(16) + " t=%d" % int(tris)
		if g is MultiMeshInstance3D:
			key = "mm %s/%s tri/inst=%d vis=%.0f" % [String(g.get_parent().name).rstrip("0123456789_-").left(18), String(rev.get(mesh, "?")).left(16), int(tris), g.visibility_range_end]
		tally[key] = float(tally.get(key, 0.0)) + tris * inst
		cnt[key] = int(cnt.get(key, 0)) + 1
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow[key] = true
	var keys: Array = tally.keys()
	keys.sort_custom(func(a, b) -> bool: return tally[a] > tally[b])
	var tot: float = 0.0
	var totn: int = 0
	for k in keys:
		tot += float(tally[k])
		totn += int(cnt[k])
	print("DUMP TOTAL tris=%.0fk nodes=%d" % [tot / 1000.0, totn])
	for k2 in keys:
		if "barge" in str(k2) or "kammhuber" in str(k2):
			print("DUMPX %s tris=%.1fk nodes=%d" % [k2, float(tally[k2]) / 1000.0, cnt[k2]])
	for i in mini(60, keys.size()):
		var k: String = keys[i]
		print("DUMP %-60s tris=%8.0fk nodes=%5d shadow=%s" % [k, float(tally[k]) / 1000.0, cnt[k], shadow.has(k)])

func _process(delta: float) -> void:
	if not in_game:
		if _menu_anchor:
			_update_menu_cam(delta)
		return
	if _perf_secs > 0.0:
		_perf_step(delta)
	_update_sim_warp(delta)
	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer < 0.0:
			_respawn_player_with_support()
	if not _manages_respawn() and Input.is_action_just_pressed("respawn"):
		_respawn_player_with_support()
	if _bail != null and (player != null or _bail.active):
		_bail.tick(delta, player)
	_respawn_watchdog(delta)
	if Input.is_action_just_pressed("next_music"):
		for gm in get_tree().get_nodes_in_group("game_music"):
			gm.call("next_track")
	_check_rearm()
	_check_ceremony(delta)
	if Input.is_action_just_pressed("start_mode_toggle"):
		GameState.start_airborne = not GameState.start_airborne
		hud.show_message("Start airborne: %s (respawn with Backspace)" % ("ON" if GameState.start_airborne else "OFF"), 2.5)
	if Input.is_action_just_pressed("airfield_cycle"):
		GameState.spawn_point = {}
		var list: Array = SIDE_AIRFIELDS[GameState.player_side]
		GameState.start_airfield = list[(list.find(GameState.start_airfield) + 1) % list.size()]
		_spawn_player()
	if Input.is_action_just_pressed("outline_toggle"):
		GameState.toggle_outlines()
		hud.show_message("Outlines %s" % ("ON" if GameState.outlines_enabled else "OFF"), 1.5)


# ---- debug / automation: godot --path . -- --shot=out.png --air --time=dusk --weather=overcast --cockpit --frames=200 --alt=900 --dz=0
var _shot_path: String = ""
var _shot_frames: int = 200
var _auto_takeoff: bool = false
var _log_t: float = 0.0

# ---- screenshot tour: one process, many locations. See _tour_begin().
var _tour_active: bool = false
var _tour_dir: String = ""
var _tour_list: Array = []
var _tour_index: int = -1
var _tour_wait: int = 0
var _tour_pop: Node = null

func _parse_debug_args() -> void:
	for a in _args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a == "--air":
			GameState.start_airborne = true
			_spawn_player()
		elif a == "--cockpit":
			_want_cockpit = true
			camera_rig.force_cockpit = true
			camera_rig.set_cockpit(true)
		elif a.begins_with("--gunner="):   # debug: step into defensive gun position N (bombers only)
			var gi: int = int(a.substr(9))
			if turrets != null and is_instance_valid(turrets):
				for i in range(gi + 1):
					turrets.cycle_view()
		elif a.begins_with("--weapon="):
			player.weapon_bombs = a.substr(9).to_lower() == "bombs"
			player.weapon_mode = 2 if player.weapon_bombs else (1 if a.substr(9).to_lower() == "rockets" else 0)
		elif a.begins_with("--overhead"):
			if a.contains("="):
				camera_rig.overhead_alt = float(a.split("=")[1])
			camera_rig.overhead = true
		elif a.begins_with("--chase="):   # debug: close chase camera distance (metres), e.g. --chase=7
			camera_rig.distance = float(a.substr(8))
			camera_rig.height = float(a.substr(8)) * 0.22
		elif a.begins_with("--orbit="):   # debug: hold a free-look orbit offset in degrees, e.g. --orbit=85,6 (side view)
			var oq: PackedStringArray = a.substr(8).split(",")
			camera_rig.set_orbit(float(oq[0]), float(oq[1]) if oq.size() > 1 else 0.0)
		elif a.begins_with("--chute="):   # debug: close-up of a parachuting pilot of the given side, e.g. --chute=Axis
			var cside: String = a.substr(8)
			get_tree().create_timer(0.3).timeout.connect(func() -> void:
				var ch: Parachute = FX.parachute(player.global_position + Vector3(0, 40, 0), "", cside)
				if ch != null:
					var cc := Camera3D.new()
					cc.fov = 50.0
					ch.add_child(cc)
					cc.position = Vector3(2.6, 1.2, 4.6)
					cc.look_at(ch.global_position + Vector3(0, 0.8, 0), Vector3.UP)
					cc.make_current())
		elif a == "--noout":
			GameState.outlines_enabled = false
		elif a == "--nohud":      # debug: clean screenshots with the HUD and hints hidden
			GameState.show_hud = false
			GameState.show_hints = false
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--hawkinge"):
			GameState.start_airfield = "hawkinge"
			_spawn_player()
		elif a.begins_with("--at="):
			var f: PackedStringArray = a.substr(5).split(",")
			var wp: Vector3 = WorldCoords.latlon_to_world(float(f[0]), float(f[1]))
			wp.y = float(f[2])
			player.reset_pose(wp, float(f[3]), true)
			camera_rig.bind(player)
		elif a.begins_with("--tour="):
			_tour_begin(a.substr(7))
		elif a == "--ammo-test":    # debug: drop the guns to 20 %, then to empty, to hear/see the warnings
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				player.ammo = int(player.stats.ammo * 0.2)
				player.weapons._check_ammo(player)
				get_tree().create_timer(4.0).timeout.connect(func() -> void:
					player.ammo = 0
					player.weapons._check_ammo(player)))
		elif a == "--plume-test":   # debug: bomb plumes in the sea ahead of the player every 4 s (water_plume visual check)
			var pt := Timer.new()
			pt.wait_time = 4.0
			pt.autostart = true
			add_child(pt)
			pt.timeout.connect(func() -> void:
				var f: Vector3 = player.get_forward()
				f.y = 0.0
				var p: Vector3 = player.global_position + f.normalized() * 300.0 + Vector3(-f.z, 0.0, f.x).normalized() * randf_range(-120.0, 120.0)
				p.y = 0.0
				print("[plume-test] plume at ", p, " player ", player.global_position)
				FX.water_plume(p, 13.0))
			FX.water_plume(player.global_position + player.get_forward() * 380.0 * Vector3(1, 0, 1), 13.0)
		elif a.begins_with("--damage-test"):   # debug: bursts of hits on the player from random sides (holes / part damage check)
			var dt := Timer.new()
			dt.wait_time = 0.35
			dt.autostart = true
			add_child(dt)
			var dt_args: PackedStringArray = (a.split("=")[1] if a.contains("=") else "2.5").split(",")
			var dmg_each: float = float(dt_args[0])
			var at_wing: bool = dt_args.size() > 1 and dt_args[1] == "wing"
			dt.timeout.connect(func() -> void:
				if player == null or player.state != Aircraft.State.ALIVE:
					return
				var dir: Vector3 = Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)).normalized()
				var aim: Vector3 = player.global_position + Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * player.hit_radius * 0.5
				if at_wing:     # the starboard wing, from above
					aim = player.global_transform * Vector3(player.hit_radius * randf_range(0.35, 0.7), 0.0, randf_range(-0.6, 0.6))
					dir = (-player.global_transform.basis.y).normalized()
				player._pending_hit = aim - dir * player.hit_radius
				player._pending_dir = dir
				player.take_damage(dmg_each, null)
				var dmm: AircraftDamageModel = player.damage_model
				print("[damage-test] decals %d parts %s" % [dmm._decals.size(), str(dmm.parts)]))
		elif a == "--crew-test":   # debug: an airfield ground-crew group just ahead of the player (figure visual check)
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				var f: Vector3 = player.get_forward()
				f.y = 0.0
				f = f.normalized()
				var cp: Vector3 = player.global_position + f * 32.0 + Vector3(-f.z, 0.0, f.x) * 14.0
				var v: GroundVehicle = GroundVehicle.create("crew", player.team, null, 0.0, 0.0, "idle")
				v.position = Vector3(cp.x, GroundKit.ground_y(cp.x, cp.z), cp.z)
				add_child(v))
		elif a.begins_with("--fire-test"):   # debug: bombs on land ahead of the player (ground fire / crater / glow check), --fire-test=<dist>
			var fdist: float = float(a.split("=")[1]) if a.contains("=") else 270.0
			var ft := func() -> void:
				var f: Vector3 = player.get_forward()
				f.y = 0.0
				f = f.normalized()
				var p: Vector3 = player.global_position + f * (fdist + randf_range(-50.0, 50.0)) + Vector3(-f.z, 0.0, f.x) * randf_range(-60.0, 60.0)
				p.y = GroundKit.ground_y(p.x, p.z)
				print("[fire-test] bomb at ", p)
				Weapons.explode_at(p, 26.0, 0.0, "none")
				CityFires.ignite(p, 1.5, true)
			get_tree().create_timer(1.0).timeout.connect(ft)
			get_tree().create_timer(2.5).timeout.connect(ft)
			get_tree().create_timer(4.0).timeout.connect(ft)
			var frt := Timer.new()
			frt.wait_time = 9.0
			frt.autostart = true
			add_child(frt)
			frt.timeout.connect(ft)
		elif a.begins_with("--break="):   # debug: damage the player's aircraft shortly after the start (wing | tip | tail | engine | fire)
			get_tree().create_timer(2.5).timeout.connect(_debug_break.bind(a.substr(8)))
		elif a == "--breach-now":   # debug: breach the dam wall of a Dam Busters day at once (flood visual check)
			get_tree().create_timer(1.5).timeout.connect(func() -> void:
				for n in get_tree().get_nodes_in_group("damageable"):
					if n is GroundStructure and String(n.get("skind")) == "dam":
						var w3: Node3D = n as Node3D
						var dn: Vector3 = -w3.global_transform.basis.z
						dn.y = 0.0
						dn = dn.normalized()
						var vp: Vector3 = w3.global_position + dn * 900.0 + Vector3(-dn.z, 0.0, dn.x) * 300.0
						vp.y = maxf(GroundKit.ground_y(vp.x, vp.z), w3.global_position.y) + 300.0
						var to: Vector3 = w3.global_position - vp
						player.reset_pose(vp, rad_to_deg(atan2(to.x, -to.z)), true, 70.0)
						n.call("take_damage", 99999.0, player)
						if _args.has("--breach-cine") and mode != null and mode.has_method("_cine_enter_flood"):
							mode.call("_cine_enter_flood"))      # the breach camera, as after a real run
		elif a == "--crash":
			get_tree().create_timer(1.0).timeout.connect(func() -> void: player.take_damage(500.0))
		elif a == "--takeoff":
			_auto_takeoff = true
		elif a.begins_with("--cloudview="):   # kind:nth:distance  (0 cumulus 1 tower 2 strato 3 cirrus 4 alto 5 lens 6 castellanus 7 cirrocumulus 8 congestus 9 stratus, 99 largest)
			var cv: PackedStringArray = a.substr(12).split(":")
			var cpos: Vector3 = WeatherManager.cloud_field.debug_cloud_pos(int(cv[0]), int(cv[1]))
			var cdist: float = float(cv[2])
			if cpos.y > 0.0:
				var fly_to := Vector3(cpos.x, cpos.y + (float(cv[3]) if cv.size() > 3 else 0.0), cpos.z + cdist)
				player.reset_pose(fly_to, 0.0, true, 120.0)
				print("CLOUDVIEW ", cpos)
			else:
				print("CLOUDVIEW none visible of kind ", cv[0])
		elif a == "--vehicle-gallery":   # debug: a row of every ground vehicle type just ahead of the player
			get_tree().create_timer(0.6).timeout.connect(func() -> void:
				var types: Array = ["car", "bus", "truck", "kubel", "jeep", "halftrack", "sherman", "panzer4", "tiger", "artillery"]
				var f: Vector3 = player.get_forward()
				f.y = 0.0
				f = f.normalized()
				var side := Vector3(-f.z, 0.0, f.x)
				var base: Vector3 = player.global_position + f * 60.0
				for i in types.size():
					var team: String = "Neutral" if types[i] in ["car", "bus"] else ("Axis" if types[i] in ["kubel", "panzer4", "tiger"] else "Allies")
					var v: GroundVehicle = GroundVehicle.create(types[i], team, null, 0.0, 0.0, "idle")
					add_child(v)
					var p: Vector3 = base + side * (float(i) - 4.5) * 13.0
					v.global_position = Vector3(p.x, GroundKit.ground_y(p.x, p.z) + 0.2, p.z)
					v.rotation.y = player.rotation.y)
		elif a == "--wind-test":   # debug: fly straight into the wind, then turn through it, logging air vs ground speed
			_lift_test = true
			_turn_test = true
			_wind_test = true
			var wv: Vector3 = WeatherManager.get_wind(player.global_position)
			var d: Vector3 = -wv.normalized()
			player.reset_pose(player.global_position, rad_to_deg(atan2(d.x, -d.z)), true, 125.0)
			print("WT wind from heading %.0f, raw %.1f units/s" % [rad_to_deg(atan2(d.x, -d.z)), wv.length()])
		elif a == "--turn-test":   # debug: steady 60 degree banked turn pulling to hold altitude
			_lift_test = true
			_turn_test = true
		elif a == "--lift-test":   # debug: level -> roll inverted -> release -> push forward -> roll upright, logging the lift
			_lift_test = true
		elif a == "--brake-test":   # debug: hold the wheel brake from 6 s (use with --takeoff)
			get_tree().create_timer(6.0).timeout.connect(func() -> void: Input.action_press("brake"))
		elif a == "--radio-test":   # debug: issue each radio order in turn
			for step in [["form", 4.0], ["attack", 8.0], ["cover", 13.0], ["rtb", 17.0], ["form", 22.0]]:
				var kind: String = step[0]
				get_tree().create_timer(float(step[1])).timeout.connect(func() -> void: Radio.order(kind))
		elif a == "--loop-test":   # debug: full back stick from level flight, logs whether a loop completes
			_mt_kind = "loop"
		elif a == "--roll-test":   # debug: full aileron for 4 s, logs the roll rate and height lost
			_mt_kind = "roll"
		elif a == "--stall-test":
			_stall_test = true
		elif a.begins_with("--height-ascii="):   # debug: lat0,lon0,lat1,lon1 -> land/sea map of the game's heights
			var q: PackedStringArray = a.substr(15).split(",")
			for row in 30:
				var line: String = ""
				var la: float = lerpf(float(q[2]), float(q[0]), float(row) / 29.0)
				for col in 80:
					var lo: float = lerpf(float(q[1]), float(q[3]), float(col) / 79.0)
					var wp: Vector3 = WorldCoords.latlon_to_world(la, lo)
					var hy: float = terrain.get_terrain_y(wp.x, wp.z)
					line += "#" if hy > 0.6 else ("+" if hy > 0.0 else ".")
				print("HA %5.2f %s" % [la, line])
		elif a == "--ship-test":   # debug: strafe the nearest ship with real bullets, then bomb another; logs hits and sinking
			get_tree().create_timer(6.0).timeout.connect(_ship_test)
		elif a.begins_with("--throttle"):
			player.throttle_target = 1.0
			player.throttle = 1.0
		elif a.begins_with("--finish-after="):
			get_tree().create_timer(float(a.substr(15))).timeout.connect(func() -> void: mode.finish(true, {"kills": 3}))
		elif a.begins_with("--pause-after="):
			get_tree().create_timer(float(a.substr(14))).timeout.connect(func() -> void:
				_pause.set_open(true)
				_ui_shot())
		elif a.begins_with("--call-after="):   # --call-after=3:restart | quit_to_menu
			var cp: PackedStringArray = a.substr(13).split(":")
			get_tree().create_timer(float(cp[0])).timeout.connect(func() -> void: call(cp[1]))
		elif a == "--autopilot":
			# debug: let the AI fly the player's aircraft (used to soak-test combat modes)
			player.player_controlled = false
			var ap: AIPilot = AIPilot.attach(player, AIPilot.Role.FIGHTER, 0.9)
			ap.detect_range = 12000.0
		elif a.begins_with("--warp="):   # debug / soak test: hold a simulation time warp for the whole run
			_warp_forced = true
			_set_sim_warp(int(a.substr(7)))
			print("[warp] forced %s for this run (contact cancel disabled)" % GameState.SIM_WARP_NAMES[GameState.sim_warp_index()])
		elif a.begins_with("--rail="):   # debug: fly a fixed straight, level line at SPEED m/s (repeatable perf runs)
			_rail_speed = float(a.substr(7))
			_rail_from = player.global_position
			_rail_dir = -player.global_transform.basis.z
			_rail_dir.y = 0.0
			_rail_dir = _rail_dir.normalized()
			_rail_basis = player.global_transform.basis
		elif a.begins_with("--perf="):   # debug: --perf=SECS[:SETTLE] frame-time profile, then quit
			var pp: PackedStringArray = a.substr(7).split(":")
			_perf_secs = float(pp[0])
			_perf_settle = float(pp[1]) if pp.size() > 1 else 10.0
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		elif a.begins_with("--audit-float="):   # debug: after SECS list visible scenery floating well above the ground, then quit
			var asecs: float = float(a.substr(14))
			get_tree().create_timer(asecs).timeout.connect(func() -> void:
				_audit_floating()
				get_tree().quit())
		elif a.begins_with("--quit-after="):
			var secs: float = float(a.substr(13))
			get_tree().create_timer(secs).timeout.connect(func() -> void:
				print("FPS ", Engine.get_frames_per_second(), " aircraft ", get_tree().get_nodes_in_group("aircraft").size())
				get_tree().quit())
	# screenshot runs (--shot= / --tour=) capture with the upscaler off: DLSS / frame
	# generation have no valid frame in --no-window runs and abort the save upstream
	var want_capture: bool = _shot_path != ""
	for a in _args:
		if a.begins_with("--tour=") or a.begins_with("--ui-shot="):
			want_capture = true
			break
	if want_capture:
		# --capture-upscaler keeps the upscaler on so the DLSS model itself can be evaluated; frame
		# generation is always off for a capture (generated frames are not in the viewport texture).
		if not _args.has("--capture-upscaler"):
			GameState.upscaler = GameState.Upscaler.OFF
		GameState.frame_gen = false
		GameState.apply_graphics()


var _stall_test: bool = false
var _st_t: float = 0.0
var _st_phase: int = 0
var _st_hold: float = 0.0
var _st_alt0: float = 0.0


## Debug: throttle off, haul back until the wing stalls, hold 2 s, then push + full power and log the recovery.
var _lift_test: bool = false
var _turn_test: bool = false
var _jit_prev_b: Basis = Basis()
var _jit_prev_w: Vector3 = Vector3.ZERO
var _jit_acc: float = 0.0
var _jit_rate: float = 0.0
var _jit_n: int = 0
var _jit_maxdt: float = 0.0
var _jit_w_before: Vector3 = Vector3.ZERO
var _jit_last_us: int = 0
var _wind_test: bool = false
var _lt_t: float = 0.0
var _lt_phase: int = 0
var _lt_phase_t: float = 0.0


func _lift_test_step(delta: float) -> void:
	_lt_t += delta
	_lt_phase_t += delta
	player.auto_level = false
	player.throttle_target = 0.75
	var bank: float = rad_to_deg(player._bank_angle())
	if _turn_test:
		if _lt_phase == 0 and _lt_phase_t > (8.0 if _wind_test else 3.0):
			_lt_phase = 1
			Input.action_press("roll_right")
		elif _lt_phase == 1 and bank > (22.0 if _args.has("--gentle") else 55.0):
			Input.action_release("roll_right")
			Input.action_press("pitch_up", 0.05 if _args.has("--gentle") else 0.3)
			_lt_phase = 2
			_lt_phase_t = 0.0
		elif _lt_phase == 2 and _lt_phase_t > 30.0:
			get_tree().quit()
		# smoothness probe: frame-to-frame change of the nose's angular rate (yaw/pitch/roll of the camera target)
		var fb: Basis = player.global_transform.basis
		if _jit_prev_b != Basis() and delta > 0.0:
			var dq: Quaternion = (_jit_prev_b.inverse() * fb).get_rotation_quaternion()
			var w: Vector3 = dq.get_euler() / delta
			_jit_w_before = _jit_prev_w
			if _jit_n > 0:
				_jit_acc += (w - _jit_prev_w).length()
			_jit_prev_w = w
			_jit_n += 1
			_jit_rate += w.length()
		_jit_prev_b = fb
		var now_us: int = Time.get_ticks_usec()
		if _jit_last_us > 0:
			_jit_maxdt = maxf(_jit_maxdt, float(now_us - _jit_last_us) * 1.0e-6)
		_jit_last_us = now_us
		_log_t += delta
		if _log_t > 1.0:
			_log_t = 0.0
			if _jit_n > 1:
				print("JIT mean_rate=%.3f mean_dw=%.4f frames=%d max_dt=%.1fms" % [_jit_rate / float(_jit_n), _jit_acc / float(_jit_n - 1), _jit_n, _jit_maxdt * 1000.0])
			_jit_maxdt = 0.0
			_jit_acc = 0.0
			_jit_rate = 0.0
			_jit_n = 0
			print("TT hw=%5.1f t=%4.1f spd=%5.1f eas=%5.1f alt=%6.1f bank=%5.1f g=%4.2f aoa=%5.1f stall=%.2f vs=%5.1f ground=%5.1f slip=%5.1f" % [player.headwind, _lt_t, player.speed, player.eas, player.get_altitude_m(), bank, player.g_load, rad_to_deg(player._alpha_signed()), player._stall_amount, player.velocity.y / 2.0, Vector2(player.velocity.x + player.wind.x, player.velocity.z + player.wind.z).length(), rad_to_deg(Vector2(player.velocity.x + player.wind.x, player.velocity.z + player.wind.z).angle_to(Vector2(player.get_forward().x, player.get_forward().z)))])
		return
	match _lt_phase:
		0:   # hands off, level
			if _lt_phase_t > 5.0:
				_lt_phase = 1
				_lt_phase_t = 0.0
				Input.action_press("roll_right")
		1:   # roll until inverted
			if absf(bank) > 165.0:
				Input.action_release("roll_right")
				_lt_phase = 2
				_lt_phase_t = 0.0
		2:   # inverted, stick free
			if _lt_phase_t > 6.0:
				_lt_phase = 3
				_lt_phase_t = 0.0
				Input.action_press("pitch_down", 0.35)
		3:   # inverted, push forward to hold level
			if _lt_phase_t > 5.0:
				Input.action_release("pitch_down")
				Input.action_press("roll_right")
				_lt_phase = 4
				_lt_phase_t = 0.0
		4:   # roll back upright
			if absf(bank) < 15.0 or _lt_phase_t > 6.0:
				Input.action_release("roll_right")
				_lt_phase = 5
				_lt_phase_t = 0.0
		5:
			if _lt_phase_t > 5.0:
				get_tree().quit()
	_log_t += delta
	if _log_t > 0.5:
		_log_t = 0.0
		print("LT t=%4.1f ph=%d spd=%5.1f alt=%6.1f bank=%6.1f pit=%5.1f lift=%5.2f g=%5.2f aoa=%5.1f stall=%.2f vs=%5.1f" % [_lt_t, _lt_phase, player.speed, player.get_altitude_m(), bank, rad_to_deg(player._pitch_angle()), player.lift_fraction, player.g_load, rad_to_deg(player._alpha_signed()), player._stall_amount, player.velocity.y / 2.0])


func _stall_test_step(delta: float) -> void:
	_st_t += delta
	if _st_phase == 0:
		player.throttle_target = 0.0
		Input.action_press("pitch_up")
		if player.stalled:
			_st_phase = 1
			_st_hold = 2.0
			_st_alt0 = player.get_altitude_m()
			print("STALLED at t=%.1f spd=%.1f" % [_st_t, player.speed])
	elif _st_phase == 1:
		_st_hold -= delta
		if _st_hold <= 0.0:
			_st_phase = 2
			Input.action_release("pitch_up")
			Input.action_press("pitch_down")
			player.throttle_target = 1.0
			print("RECOVERY INPUT at t=%.1f spd=%.1f" % [_st_t, player.speed])
	elif _st_phase == 2 and not player.stalled and player.speed > player.stats.stall_speed * 1.15:
		print("RECOVERED at t=%.1f spd=%.1f alt lost=%.0f m" % [_st_t, player.speed, _st_alt0 - player.get_altitude_m()])
		_st_phase = 3
		Input.action_release("pitch_down")
	_log_t += delta
	if _log_t > 0.4:
		_log_t = 0.0
		print("t=%.1f ph=%d spd=%.0f alt=%.0f stall=%s amt=%.2f pitch=%.0f bank=%.0f" % [_st_t, _st_phase, player.speed, player.altitude_agl, player.stalled, player._stall_amount, rad_to_deg(player._pitch_angle()), rad_to_deg(player._bank_angle())])
	if _st_t > 45.0 or _st_phase == 3 and _st_t > 0.0 and _st_hold < -6.0:
		get_tree().quit()
	if _st_phase == 3:
		_st_hold -= delta


var _mt_kind: String = ""
var _mt_t: float = 0.0
var _mt_log: float = 0.0
var _mt_acc: float = 0.0
var _mt_prev: Basis = Basis()
var _mt_alt0: float = 0.0


## Loop / roll test. Runs on the render frame clock via the aircraft's own transform deltas.
func _maneuver_test_step(delta: float) -> void:
	_mt_t += delta
	player.throttle_target = 1.0
	if _mt_t < 3.0:
		player.auto_level = false
		_mt_prev = player.global_transform.basis
		_mt_alt0 = player.get_altitude_m()
		return
	var b: Basis = player.global_transform.basis
	var rel: Basis = _mt_prev.inverse() * b
	var e: Vector3 = rel.get_euler()
	_mt_acc += e.x if _mt_kind == "loop" else -e.z
	_mt_prev = b
	if _mt_kind == "loop":
		Input.action_press("pitch_up", 1.0)
	elif _mt_t < 7.0:
		Input.action_press("roll_right", 1.0)
	else:
		Input.action_release("roll_right")
	_mt_log += delta
	if _mt_log > 0.5:
		_mt_log = 0.0
		print("MT %s t=%4.1f turned=%6.1f spd=%5.1f alt=%6.1f dalt=%6.1f aoa=%5.1f g=%4.1f stall=%.2f pr=%.2f rr=%.2f pitch=%5.1f bank=%6.1f" % [_mt_kind, _mt_t - 3.0, rad_to_deg(_mt_acc), player.speed, player.get_altitude_m(), player.get_altitude_m() - _mt_alt0, rad_to_deg(player._alpha_signed()), player.g_load, player._stall_amount, player._pitch_rate, player._roll_rate, rad_to_deg(player._pitch_angle()), rad_to_deg(player._bank_angle())])
	if _mt_t > (25.0 if _mt_kind == "loop" else 10.0):
		print("MT RESULT %s turned %.0f deg" % [_mt_kind, rad_to_deg(_mt_acc)])
		get_tree().quit()


func _physics_process(delta: float) -> void:
	if not in_game:
		return
	if _mt_kind != "":
		_maneuver_test_step(delta)
	if _stall_test:
		_stall_test_step(delta)
	if _lift_test:
		_lift_test_step(delta)
	if _rail_speed > 0.0:
		_rail_step(delta)
	if _auto_takeoff:
		Input.action_press("throttle_up")
		if player.speed > 46.0:
			Input.action_press("pitch_up", 0.5)
		_log_t += delta
		if _log_t > 0.5:
			_log_t = 0.0
			print("t=%.1f spd=%.1f alt=%.1f gnd=%s stall=%s pitch=%.1f thr=%.2f" % [Time.get_ticks_msec() / 1000.0, player.speed, player.altitude_agl, player.on_ground, player.stalled, rad_to_deg(player._pitch_angle()), player.throttle])
	if _shot_path != "":
		if _args.has("--plate"):      # story plate: no HUD or overlays in the picture
			for c in get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
		# --freeze holds the airframe still for a shot, so the same pose can be captured twice (A/B testing
		# the upscaler model, or any before/after): the chase camera then does not drift while frames count.
		if _args.has("--freeze") and player != null and is_instance_valid(player):
			player.process_mode = Node.PROCESS_MODE_DISABLED
		_shot_frames -= 1
		if _shot_frames == 0:
			print("FPS ", Engine.get_frames_per_second(), " chunks ", terrain._chunks.size(), " draws ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			if _args.has("--dump-near"):
				_dump_near(player.global_position, 90.0)
			var img: Image = get_viewport().get_texture().get_image()
			if img == null or img.is_empty():
				push_error("[shot] empty viewport image, cannot save %s" % _shot_path)
			else:
				var err: Error = img.save_png(_shot_path)
				if err != OK:
					push_error("[shot] save_png failed (%s) for %s" % [err, _shot_path])
				else:
					print("[shot] saved %s (%dx%d)" % [ProjectSettings.globalize_path(_shot_path), img.get_width(), img.get_height()])
			get_tree().quit()
	if _tour_active:
		_tour_tick()


## Screenshot tour: read a JSON list of locations and save one PNG per stop in a
## single process (so the scenery loads once). JSON:
##   { "dir": "out", "shots": [ { "name": "01", "lat": .., "lon": ..,
##     "alt": .., "hdg": .., "speed": .., "settle": 150 }, ... ] }
func _tour_begin(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[tour] cannot open %s" % path)
		get_tree().quit()
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("shots"):
		push_error("[tour] bad json in %s" % path)
		get_tree().quit()
		return
	_tour_dir = String(data.get("dir", ""))
	for s in data["shots"]:
		_tour_list.append(s)
	for c in get_children():
		if c is WorldPopulator:
			_tour_pop = c
	_tour_active = true
	print("[tour] %d stops -> %s" % [_tour_list.size(), _tour_dir])
	_tour_step()


func _tour_step() -> void:
	_tour_index += 1
	if _tour_index >= _tour_list.size():
		print("[tour] done (%d shots)" % _tour_list.size())
		get_tree().quit()
		return
	var s: Dictionary = _tour_list[_tour_index]
	var wp: Vector3 = WorldCoords.latlon_to_world(float(s.get("lat", 51.3)), float(s.get("lon", 1.0)))
	wp.y = float(s.get("alt", 600.0))
	if s.has("time"):
		TimeOfDay.set_preset(String(s["time"]))
	if s.has("weather"):
		WeatherManager.set_weather(String(s["weather"]), 0.1)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.reset_pose(wp, float(s.get("hdg", 90.0)), true, float(s.get("speed", 160.0)))
	# Give the airframe an attitude (bank / pitch, degrees) so shots are not dead level.
	var roll: float = deg_to_rad(float(s.get("bank", 0.0)))
	var pitch: float = deg_to_rad(float(s.get("pitch", 0.0)))
	if roll != 0.0 or pitch != 0.0:
		var b: Basis = player.global_transform.basis
		b = b * Basis(Vector3(0.0, 0.0, 1.0), roll)    # roll about local Z (forward)
		b = b * Basis(Vector3(1.0, 0.0, 0.0), pitch)   # pitch about local X (right)
		player.global_transform = Transform3D(b.orthonormalized(), player.global_position)
	camera_rig.bind(player)
	camera_rig.set_cockpit(bool(s.get("cockpit", false)))
	camera_rig.set_orbit(float(s.get("cam_yaw", 0.0)), float(s.get("cam_pitch", 0.0)))
	player.process_mode = Node.PROCESS_MODE_DISABLED   # hold the pose steady for the shot
	_tour_wait = int(s.get("settle", 240))
	print("[tour] %d/%d %s  %s" % [_tour_index + 1, _tour_list.size(), String(s.get("name", "?")), str(wp)])


func _tour_tick() -> void:
	if not terrain.is_settled():
		return   # wait for the tiles around the new location to stream in
	if _tour_pop != null and is_instance_valid(_tour_pop):
		var pend: int = int(_tour_pop.get("pending"))
		if pend > 0 and pend < 900:
			return   # still building / streaming sites around the new location
	_tour_wait -= 1
	if _tour_wait > 0:
		return
	var s: Dictionary = _tour_list[_tour_index]
	var nm: String = String(s.get("name", "%02d" % _tour_index))
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("[tour] null image at %s" % nm)
	else:
		var out: String = _tour_dir.path_join(nm + ".png")
		var err: Error = img.save_png(out)
		if err != OK:
			push_error("[tour] save_png failed (%s) for %s" % [err, out])
		else:
			print("[tour] saved %s (%dx%d)" % [ProjectSettings.globalize_path(out), img.get_width(), img.get_height()])
	_tour_step()


func _debug_open_options() -> void:
	# only force the Controls page when no page was asked for, so a capture run can open any settings page
	SettingsMenu.start_on_controls = OS.get_environment("WW2_SETTINGS_PAGE") == ""
	add_child(SettingsMenu.new())


func _dump_near(c: Vector3, r: float) -> void:
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var v := n as VisualInstance3D
		if v.global_position.distance_to(c) < r:
			print("NEAR ", v.get_path(), " ", v.global_position, " ", v.get_aabb().size)


func _ship_test() -> void:
	var ships: Array = get_tree().get_nodes_in_group("ship").filter(func(n: Node) -> bool: return str(n.get("stype")) in ["collier", "destroyer", "trawler"])
	ships.sort_custom(func(x: Node, y: Node) -> bool:
		return (x as Node3D).global_position.distance_to(player.global_position) < (y as Node3D).global_position.distance_to(player.global_position))
	print("[ship-test] ships in world: %d" % ships.size())
	if ships.size() < 2:
		return
	var a = ships[0]
	var b = ships[1]
	var foe: String = "Axis" if str(a.get("team")) == "Allies" else "Allies"
	print("[ship-test] A %s %s hp=%.0f r=%.1f" % [a.get("stype"), a.get("team"), a.get("health"), a.get("hit_radius")])
	# strafe: 20 mm-ish rounds from 400 m up and behind, aimed at the hull
	for i in 160:
		var tgt: Vector3 = (a as Node3D).global_position + Vector3(randf_range(-6, 6), 2.0, randf_range(-6, 6))
		var from: Vector3 = tgt + Vector3(0, 250, 300)
		Weapons.fire_bullet(from, (tgt - from).normalized() * 800.0, foe, null, 9.0, false, 2.0)
	# bomb the second ship from 300 m
	var bp: Vector3 = (b as Node3D).global_position + Vector3(0, 300, 0)
	Weapons.drop_bomb(bp, Vector3.ZERO, "Axis" if str(b.get("team")) == "Allies" else "Allies", null, 250.0, 30.0)
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		print("[ship-test] A hp=%.0f dead=%s  B hp=%.0f dead=%s" % [a.get("health"), str(a.get("is_dead")), b.get("health"), str(b.get("is_dead"))]))
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("[ship-test] after 30 s: A y=%.1f  B y=%.1f" % [(a as Node3D).global_position.y, (b as Node3D).global_position.y]))



## Debug (--call-after=N:_look_test): hold the right stick and log where the chase camera sits
## relative to the aircraft (azimuth from straight behind, elevation, distance).
func _look_test() -> void:
	for step in [["X+", JOY_AXIS_RIGHT_X, 1.0], ["X-", JOY_AXIS_RIGHT_X, -1.0], ["Y+", JOY_AXIS_RIGHT_Y, 1.0], ["Y-", JOY_AXIS_RIGHT_Y, -1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = step[1]
		ev.axis_value = step[2]
		Input.parse_input_event(ev)
		for i in 6:
			await get_tree().create_timer(0.25).timeout
			_look_log(String(step[0]))
		ev = InputEventJoypadMotion.new()
		ev.axis = step[1]
		ev.axis_value = 0.0
		Input.parse_input_event(ev)
		await get_tree().create_timer(1.5).timeout
		_look_log(String(step[0]) + " released")
	get_tree().quit()


func _look_log(tag: String) -> void:
	var rel: Vector3 = camera_rig.chase_cam.global_position - player.global_position
	var f: Vector3 = player.get_forward()
	var behind_az: float = rad_to_deg(Vector2(-f.x, -f.z).angle_to(Vector2(rel.x, rel.z)))
	print("[look] %-12s az=%7.1f el=%6.1f dist=%6.1f" % [tag, behind_az, rad_to_deg(asin(rel.y / maxf(rel.length(), 0.001))), rel.length()])


var _photo_busy: bool = false


## Clean screenshot (no HUD) saved as PNG into Pictures/WW2 Channel Air War (or the game's user folder).
func _take_photo() -> void:
	if _photo_busy or hud == null:
		return
	_photo_busy = true
	var was_visible: bool = hud.visible
	hud.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	hud.visible = was_visible
	var dir: String = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	dir = dir.path_join("WW2 Channel Air War") if dir != "" else ProjectSettings.globalize_path("user://screenshots")
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		dir = ProjectSettings.globalize_path("user://screenshots")
		DirAccess.make_dir_recursive_absolute(dir)
	var t: Dictionary = Time.get_datetime_dict_from_system()
	var path: String = dir.path_join("ww2_%04d%02d%02d_%02d%02d%02d.png" % [t.year, t.month, t.day, t.hour, t.minute, t.second])
	var err: int = img.save_png(path)
	if hud != null and hud.has_method("show_message"):
		hud.show_message(("Photo saved: " + path) if err == OK else "Could not save the photo", 3.5)
	_photo_busy = false


func _debug_break(how: String) -> void:
	var dm: AircraftDamageModel = player.damage_model
	if how == "wing":
		dm.wing_lost["wing_r"] = 1
		dm.lose_wing("wing_r", null)
	elif how == "tip":
		dm.lose_wing("wing_l", null)
	elif how == "tail":
		dm.lose_tail(null)
	elif how == "engine":
		dm._init_engines()
		dm._engine_fail(0, true)
	elif how == "fire":
		player.health = player.stats.max_health * 0.3
		for c in player.get_children():
			if c is AircraftDamageFX:
				(c as AircraftDamageFX)._ignite()


## Debug (--audit-float=SECS): scenery whose origin sits far above the terrain under it, grouped by where it lives.
func _audit_floating() -> void:
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain == null:
		print("[audit] no terrain")
		return
	var skip: Array = ["cloud", "star", "sun", "moon", "sky", "rain", "bird", "balloon", "chute", "tracer", "bullet", "fx", "smoke", "camera", "hud", "contrail", "searchlight", "beam", "flak", "flare", "projectile", "bomb", "missile", "rocket", "airship", "kite", "intact_balloon", "zeppelin", "blimp"]
	var agg: Dictionary = {}
	var checked: int = 0
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	for n in find_children("*", "Node3D", true, false):
		var n3: Node3D = n as Node3D
		var is_mi: bool = n3 is MeshInstance3D
		var is_mm: bool = n3 is MultiMeshInstance3D
		if not (is_mi or is_mm) or not n3.is_visible_in_tree():
			continue
		var bad: bool = false
		var path: String = ""
		var q: Node = n3
		var depth: int = 0
		while q != null and q != self:
			var ln: String = String(q.name).to_lower()
			for k in skip:
				if ln.contains(String(k)):
					bad = true
			if q is Aircraft or q is Camera3D or q is CanvasItem or q is BarrageBalloon:
				bad = true
			if depth < 5:
				var nm: String = String(q.name)
				var j: int = nm.length()
				while j > 0 and (nm[j - 1].is_valid_int() or nm[j - 1] == "@"):
					j -= 1
				path = nm.substr(0, j) + "/" + path
			depth += 1
			q = q.get_parent()
		if bad:
			continue
		var pts: Array = []
		if is_mi:
			var mesh: Mesh = (n3 as MeshInstance3D).mesh
			if mesh == null:
				continue
			var bb: AABB = mesh.get_aabb()
			var lowest: Vector3 = n3.global_position
			for ci in 8:
				var cp2: Vector3 = n3.global_transform * bb.get_endpoint(ci)
				if cp2.y < lowest.y:
					lowest = cp2
			pts.append(lowest)
		else:
			var mm: MultiMesh = (n3 as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			var step: int = maxi(mm.instance_count / 600, 1)
			for i in range(0, mm.instance_count, step):
				pts.append(n3.global_transform * mm.get_instance_transform(i).origin + Vector3(0.0, mm.mesh.get_aabb().position.y * mm.get_instance_transform(i).basis.get_scale().y if mm.mesh != null else 0.0, 0.0))
		for p in pts:
			var pv: Vector3 = p
			checked += 1
			var dy: float = pv.y - float(terrain.call("get_height_at", pv))
			if dy > 6.0:
				var key: String = path + (" [multimesh]" if is_mm else "")
				if not agg.has(key):
					agg[key] = [0, 0.0, pv, pv.distance_to(cp)]
				var e: Array = agg[key]
				e[0] = int(e[0]) + 1
				if dy > float(e[1]):
					e[1] = dy
					e[2] = pv
	print("[audit] checked ", checked, " points; floating groups: ", agg.size())
	var keys: Array = agg.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool: return float((agg[x] as Array)[1]) > float((agg[y] as Array)[1]))
	for k in keys:
		var e2: Array = agg[k]
		var wp: Vector3 = e2[2]
		print("[audit] %s  n=%d  max_above=%.0f  at=(%.0f, %.0f, %.0f)  dist=%.0f" % [k, int(e2[0]), float(e2[1]), wp.x, wp.y, wp.z, float(e2[3])])
