class_name MapAssets
extends RefCounted
## Catalogue of placeable asset keys for hand-made map edits (see MapEdits): each key maps to a label, a
## category ("building" or "prop") and a builder returning a fresh Node3D with its base at local y = 0.
## WorldPopulator positions and yaws the node; the map-editor app lists keys() and their labels.
## Every model reuses an existing builder in scripts/ground/ - no new geometry is authored here.
##
##   var n: Node3D = MapAssets.build("church")

static var _catalog: Dictionary = {}


## Every placeable key, sorted.
static func keys() -> Array:
	var out: Array = _ensure().keys()
	out.sort()
	return out


static func label(key: String) -> String:
	var e: Variant = _ensure().get(key)
	return "" if e == null else str((e as Dictionary)["label"])


static func category(key: String) -> String:
	var e: Variant = _ensure().get(key)
	return "" if e == null else str((e as Dictionary)["cat"])


static func has(key: String) -> bool:
	return _ensure().has(key)


## A fresh Node3D for `key`, or null for an unknown key. The node's base sits at its local origin.
static func build(key: String) -> Node3D:
	var e: Variant = _ensure().get(key)
	if e == null:
		return null
	return ((e as Dictionary)["make"] as Callable).call() as Node3D


static func _add(key: String, label_s: String, cat: String, make: Callable) -> void:
	_catalog[key] = {"label": label_s, "cat": cat, "make": make}


## Wrap an ArrayMesh builder (AirfieldAssets / CampAssets / Scatter) in a MeshInstance3D whose base is at 0.
static func _wrap(c: Callable) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = c.call() as Mesh
	mi.cast_shadow = Scatter.scenery_shadow_mode()
	return mi


## A house unit (Scatter.house_mesh) scaled to a real footprint, lifted so its base sits at y = 0.
static func _house(variant: int, w: float, h: float, d: float) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Scatter.house_mesh(variant)
	mi.scale = Vector3(w, h, d)
	mi.position = Vector3(0.0, h * 0.5, 0.0)
	root.add_child(mi)
	return root


static func _mesh(c: Callable) -> Callable:
	return Callable(MapAssets, "_wrap").bind(c)


static func _h(v: int, w: float, h: float, d: float) -> Callable:
	return Callable(MapAssets, "_house").bind(v, w, h, d)


static func _ensure() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	# --- buildings: the ten house units plus the church, windmill and the farm buildings ---
	_add("house_terrace", "Brick terrace house", "building", _h(0, 7.0, 7.0, 9.0))
	_add("house_terrace_soot", "Smoke-darkened terrace house", "building", _h(1, 7.0, 7.0, 9.0))
	_add("house_semi", "Semi-detached pair", "building", _h(2, 11.0, 7.0, 9.0))
	_add("house_cottage", "Cottage", "building", _h(3, 8.0, 5.5, 9.0))
	_add("house_shop", "Corner shop", "building", _h(4, 8.0, 8.0, 9.0))
	_add("house_villa", "Victorian villa", "building", _h(5, 9.0, 9.0, 10.0))
	_add("house_warehouse", "Warehouse", "building", _h(6, 12.0, 10.0, 11.0))
	_add("house_works", "Works / factory", "building", _h(7, 16.0, 7.0, 12.0))
	_add("house_cinema", "Cinema / picture palace", "building", _h(8, 16.0, 11.0, 14.0))
	_add("house_station", "Railway station front", "building", _h(9, 18.0, 8.0, 12.0))
	_add("church", "Parish church", "building", Callable(Landmarks, "church"))
	_add("windmill", "Windmill", "building", Callable(Landmarks, "windmill"))
	_add("barn", "Farm barn", "building", _h(1, 26.0, 9.0, 15.0))
	_add("shed", "Farm shed", "building", _h(0, 10.0, 4.0, 7.0))
	# --- props: trees and hedges (Scatter) ---
	_add("tree_broadleaf", "Broadleaf tree", "prop", _mesh(Callable(Scatter, "tree_mesh").bind(true)))
	_add("tree_conifer", "Conifer", "prop", _mesh(Callable(Scatter, "tree_mesh").bind(false)))
	_add("hedge", "Hedge section", "prop", _mesh(Callable(Scatter, "hedge_mesh")))
	_add("pole", "Timber pole", "prop", _mesh(Callable(Scatter, "pole_mesh")))
	_add("hedgehog", "Hedgehog obstacle", "prop", _mesh(Callable(Scatter, "hedgehog_mesh")))
	_add("dragon_teeth", "Dragon's teeth", "prop", _mesh(Callable(Scatter, "tooth_mesh")))

	# --- props: airfield clutter (AirfieldAssets) ---
	_add("nissen", "Nissen hut", "prop", _mesh(Callable(AirfieldAssets, "nissen").bind("Allies")))
	_add("blister_hangar", "Blister hangar", "prop", _mesh(Callable(AirfieldAssets, "blister").bind("Allies")))
	_add("tent", "Ridge tent", "prop", _mesh(Callable(AirfieldAssets, "tent").bind("Allies")))
	_add("marquee", "Marquee", "prop", _mesh(Callable(AirfieldAssets, "marquee").bind("Allies")))
	_add("t2_hangar", "T2 hangar", "prop", _mesh(Callable(AirfieldAssets, "t2_hangar").bind("Allies")))
	_add("t1_hangar", "T1 hangar", "prop", _mesh(Callable(AirfieldAssets, "t1_hangar").bind("Allies")))
	_add("lw_hangar", "Luftwaffe hangar", "prop", _mesh(Callable(AirfieldAssets, "lw_hangar").bind("Axis")))
	_add("watch_office", "Watch office", "prop", _mesh(Callable(AirfieldAssets, "lw_watch_office")))
	_add("revetment", "Aircraft revetment", "prop", _mesh(Callable(AirfieldAssets, "revetment").bind("Allies")))
	_add("fuel_tank", "Bulk fuel tank", "prop", _mesh(Callable(AirfieldAssets, "fuel_tank")))
	_add("bomb_bank", "Bomb store bank", "prop", _mesh(Callable(AirfieldAssets, "bomb_bank")))
	_add("dummy_aircraft", "Dummy aircraft", "prop", _mesh(Callable(AirfieldAssets, "dummy_aircraft").bind("Allies")))
	_add("truck", "Lorry", "prop", _mesh(Callable(AirfieldAssets, "truck").bind("Allies")))
	_add("halftrack", "Halftrack", "prop", _mesh(Callable(AirfieldAssets, "halftrack").bind("Allies")))
	_add("tank", "Tank", "prop", _mesh(Callable(AirfieldAssets, "tank").bind("Allies")))
	_add("field_gun", "Field gun", "prop", _mesh(Callable(AirfieldAssets, "field_gun").bind("Allies")))
	_add("crate_stack", "Crate stack", "prop", _mesh(Callable(AirfieldAssets, "crate_stack").bind("Allies")))
	_add("drum_stack", "Drum stack", "prop", _mesh(Callable(AirfieldAssets, "drum_stack").bind("Allies")))
	_add("chance_light", "Chance light", "prop", _mesh(Callable(AirfieldAssets, "chance_light")))
	_add("landing_t", "Landing T", "prop", _mesh(Callable(AirfieldAssets, "landing_t")))
	_add("camo_net", "Camouflage net", "prop", _mesh(Callable(AirfieldAssets, "camo_net").bind("Allies")))
	_add("e_pen", "E-pen", "prop", _mesh(Callable(AirfieldAssets, "e_pen")))
	_add("boundary_marker", "Boundary marker", "prop", _mesh(Callable(AirfieldAssets, "boundary_marker")))

	# --- props: camp clutter (CampAssets) ---
	_add("guard_tower", "Guard tower", "prop", _mesh(Callable(CampAssets, "guard_tower").bind("pow")))
	_add("barrack_hut", "Barrack hut", "prop", _mesh(Callable(CampAssets, "barrack_hut").bind("stalag")))
	_add("cookhouse", "Cookhouse", "prop", _mesh(Callable(CampAssets, "cookhouse")))
	_add("water_tower", "Water tower", "prop", _mesh(Callable(CampAssets, "water_tower")))
	_add("ammo_bay", "Ammunition bay", "prop", _mesh(Callable(CampAssets, "ammo_bay").bind("Allies")))
	_add("drum_dump", "Fuel drum dump", "prop", _mesh(Callable(CampAssets, "drum_dump").bind("Allies")))
	_add("camo_tent", "Camouflaged tent", "prop", _mesh(Callable(CampAssets, "camo_tent").bind("Allies", 0)))
	_add("slit_trench", "Slit trench", "prop", _mesh(Callable(CampAssets, "slit_trench")))
	_add("goalposts", "Goalposts", "prop", _mesh(Callable(CampAssets, "goalposts")))
	_add("fence_bay", "Wire fence bay", "prop", _mesh(Callable(CampAssets, "fence_bay").bind(true)))
	_add("concertina", "Concertina wire", "prop", _mesh(Callable(CampAssets, "concertina")))
	_add("camp_gate", "Camp gate", "prop", _mesh(Callable(CampAssets, "gate").bind("Allies")))
	return _catalog
