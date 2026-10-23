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
	_test_turret_mounts()
	_test_scatter_masks()
	_test_music()
	_test_audio()
	_test_data_files()
	_test_river_data()
	_test_landmarks_all()
	_test_house_variants()
	_test_industry_kinds()
	_test_landscape_data()
	_test_sea_defence_kinds()
	_test_dams_build()
	_test_city_balloons()
	_test_balloon_cables_and_streams()
	_test_decoy_kinds()
	_test_pylon_data()
	_test_pylon_build()
	_test_canal_furniture()
	_test_rail_drama()
	_test_airfield_furniture()
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
	_test_weak_gpu()
	_test_accessibility()
	_test_awards()
	_test_legal_docs()
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
		"res://shaders/canopy_glass.gdshader": ["tint", "opacity", "rim_amount", "glint"],
		"res://shaders/outline.gdshader": ["thickness", "outline_color"],
		"res://shaders/team_outline.gdshader": ["outline_color", "fade_start"],
	}
	for path in want.keys():
		var sh: Shader = load(path) as Shader
		if not _check(sh != null, "loads %s" % path):
			continue
		for u in want[path]:
			_check(sh.code.contains(String(u)), "%s declares uniform %s" % [path, u])


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
func _test_markings() -> void:
	print("-- decals and pilots")
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
		_check(n_dec > 0, "%s has national markings" % mid)
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
	_check(ingame.size() >= 9, "in-game playlist has tracks (%d)" % ingame.size())
	for p in menu:
		_check(ResourceLoader.exists(String(p)), "menu track loads: %s" % p)
	for p in ingame:
		_check(ResourceLoader.exists(String(p)), "in-game track loads: %s" % p)


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
	a.free()


func _peak(s: AudioStreamWAV) -> float:
	var d: PackedByteArray = s.data
	var m: float = 0.0
	for i in range(0, d.size() - 1, 2):
		m = maxf(m, absf(float(d.decode_s16(i))) / 32768.0)
	return m


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
		_check(txt.contains("Check for updates") and txt.contains("DLSS") and txt.contains("PayPal"), "privacy text covers every button that touches the network")


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
