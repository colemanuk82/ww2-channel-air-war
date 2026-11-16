extends RefCounted

## Props of the living war (agent c2, phases 4-5). Five small things, all low poly and built from boxes and cylinders
## (GroundKit parts through AirfieldAssets._build, like the ambulance), nothing from other games:
##
##  * a fire engine (English ground) or an Opel Blitz lorry (German ground) that drives up the nearest road to a crash
##    scene the way the ambulance does, and parks 12 m short of it on the other side of the road, with 2-3 firemen
##    (the dark ARP outfit) by it. Used by WarReactions._add_rig / _add_engine.
##  * a Kommandantur flag (a red flag with a white disc, no insignia) on the roof of an Axis-held town hall. Used by
##    WorldPopulator._build_city.
##  * a German sentry pair at each Axis-held harbour (port_ / dock_ sites). Used by WorldPopulator._site_people.
##  * a field kitchen (a two-wheeled trailer with a chimney) with 4-6 men round it, and one or two horse-drawn supply
##    wagons (FarmPeople's led horse and cart, as static meshes) at the field edge of an Axis airfield. Used by
##    AirfieldPeople.populate, before plan(), so the Grid keeps the men off everything else.
##
## Loaded with preload from the callers (no class_name, so no editor import is needed). The Kind enum, the figure shader
## and the dress list are NOT touched: the men reuse the existing kinds and the civilian outfits.

const RED := Color(0.72, 0.08, 0.06)
const BLACK := Color(0.08, 0.08, 0.08)
const BRASS := Color(0.82, 0.67, 0.25)
const WOOD := Color(0.55, 0.42, 0.22)
const GREY := Color(0.36, 0.38, 0.37)
const CANVAS := Color(0.40, 0.40, 0.34)
const IRON := Color(0.30, 0.30, 0.32)
const GLASS := Color(0.20, 0.25, 0.28)
const FLAG_RED := Color(0.80, 0.05, 0.04)
const WHITE := Color(0.94, 0.94, 0.90)
const FIELD_GREEN := Color(0.33, 0.35, 0.30)
## the Town Hall's clock tower finial tops out about 34.5 m above its ground at scale 1 (TownModels.town_hall; the hipped roof is 16.9 m and the
## tower stands in the middle of it, so a flag on the roof would be inside the tower: the pole stands on the finial)
const TOWN_HALL_TOP: float = 34.4
const FLAG_POLE_H: float = 6.0

static var _cache: Dictionary = {}
static var _vcol_mat: StandardMaterial3D = null


# ------------------------------------------------------------------ rules (pure, tested)

## The vehicle that comes up the road to a crash scene: a fire engine on English ground, a lorry on German ground.
static func rig_kind(crew: String) -> String:
	return "opel_blitz" if crew == "Axis" else "fire_engine"


## A Kommandantur flag flies over an Axis-held town of size 2 and up that has a town hall (as the garrison does).
static func flag_flown(team: String, size: int, civic: Array) -> bool:
	if team != "Axis" or size < 2:
		return false
	for cv in civic:
		var cd: Dictionary = cv
		if str(cd.get("kind", "")) == "townhall" and cd.has("pos"):
			return true
	return false


## Sentries stand at an Axis-held harbour (a port or a dock site), never at any other site.
static func harbour_guarded(team: String, key: String) -> bool:
	return team == "Axis" and (key.begins_with("port_") or key.begins_with("dock_"))


## The field kitchen and its wagons are Luftwaffe (Axis) fields only.
static func camp_allowed(team: String) -> bool:
	return team == "Axis"


# ------------------------------------------------------------------ meshes (built once)

static func _cached(key: String, parts: Array) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var m: ArrayMesh = AirfieldAssets._build(parts)
	_cache[key] = m
	return m


## A period fire engine (Dennis-style): red pump body and cab, a wooden ladder carried on top, a brass bell, a hose
## reel at the back. The front is -Z, as the ambulance.
static func fire_engine_mesh() -> ArrayMesh:
	if _cache.has("fire"):
		return _cache["fire"]
	var p: Array = []
	p.append(GroundKit.box_part(Vector3(1.9, 0.3, 6.2), Vector3(0.0, 0.7, -0.2), BLACK))
	for wz in [-2.3, 1.7]:
		for wx in [-1.0, 1.0]:
			p.append(GroundKit.cyl_part(0.5, 0.5, 0.36, Vector3(wx, 0.5, wz), BLACK, Vector3(0, 0, 90), 10))
			p.append(GroundKit.cyl_part(0.24, 0.24, 0.38, Vector3(wx, 0.5, wz), BRASS.darkened(0.4), Vector3(0, 0, 90), 8, false))
	# cab, with its windscreen
	p.append(GroundKit.box_part(Vector3(2.0, 1.3, 1.9), Vector3(0.0, 1.55, -2.3), RED))
	p.append(GroundKit.box_part(Vector3(1.7, 0.5, 0.05), Vector3(0.0, 1.8, -3.27), GLASS, Vector3(-8, 0, 0), false))
	p.append(GroundKit.cyl_part(0.2, 0.2, 0.2, Vector3(0.0, 2.3, -1.9), BRASS, Vector3.ZERO, 10, false))
	# pump body with its dark locker band, and the ladder on top
	p.append(GroundKit.box_part(Vector3(2.0, 1.2, 3.4), Vector3(0.0, 1.4, 0.7), RED))
	p.append(GroundKit.box_part(Vector3(2.04, 0.4, 3.44), Vector3(0.0, 0.92, 0.7), BLACK))
	for lx in [-0.45, 0.45]:
		p.append(GroundKit.box_part(Vector3(0.1, 0.12, 4.7), Vector3(lx, 2.12, 1.15), WOOD, Vector3.ZERO, false))
	for k in 5:
		p.append(GroundKit.box_part(Vector3(0.9, 0.05, 0.05), Vector3(0.0, 2.14, -0.6 + float(k) * 0.9), WOOD, Vector3.ZERO, false))
	# hose reel at the back, and the brass headlamps
	p.append(GroundKit.cyl_part(0.4, 0.4, 0.5, Vector3(0.0, 1.6, 2.5), IRON, Vector3(90, 0, 0), 10))
	for lx2 in [-0.75, 0.75]:
		p.append(GroundKit.cyl_part(0.12, 0.12, 0.1, Vector3(lx2, 1.0, -3.3), BRASS, Vector3(90, 0, 0), 8, false))
	return _cached("fire", p)


## A grey Opel Blitz lorry: cab and bonnet, a canvas-covered bed. Front -Z.
static func opel_blitz_mesh() -> ArrayMesh:
	if _cache.has("blitz"):
		return _cache["blitz"]
	var p: Array = []
	p.append(GroundKit.box_part(Vector3(1.4, 0.25, 5.2), Vector3(0.0, 0.7, -0.2), BLACK))
	for wz in [-2.2, 1.6]:
		for wx in [-0.9, 0.9]:
			p.append(GroundKit.cyl_part(0.5, 0.5, 0.3, Vector3(wx, 0.5, wz), BLACK, Vector3(0, 0, 90), 10))
	p.append(GroundKit.box_part(Vector3(1.9, 1.35, 1.7), Vector3(0.0, 1.6, -2.0), GREY))
	p.append(GroundKit.box_part(Vector3(1.6, 0.5, 0.05), Vector3(0.0, 1.85, -2.88), GLASS, Vector3(-8, 0, 0), false))
	p.append(GroundKit.cyl_part(0.45, 0.45, 1.3, Vector3(0.0, 1.05, -3.0), GREY, Vector3(90, 0, 0), 10))
	p.append(GroundKit.box_part(Vector3(0.9, 0.5, 0.06), Vector3(0.0, 1.0, -3.66), BLACK))
	p.append(GroundKit.box_part(Vector3(2.0, 0.12, 3.9), Vector3(0.0, 1.12, 1.1), GREY.darkened(0.1)))
	p.append(GroundKit.box_part(Vector3(1.9, 0.85, 3.4), Vector3(0.0, 1.85, 1.0), CANVAS))
	for lx in [-0.6, 0.6]:
		p.append(GroundKit.cyl_part(0.11, 0.11, 0.1, Vector3(lx, 1.2, -3.6), Color(0.75, 0.74, 0.66), Vector3(90, 0, 0), 8, false))
	return _cached("blitz", p)


## The Kommandantur flag: an iron pole, a plain red flag with a white disc on each side. No insignia.
static func flag_mesh() -> ArrayMesh:
	if _cache.has("flag"):
		return _cache["flag"]
	var p: Array = []
	p.append(GroundKit.cyl_part(0.07, 0.07, FLAG_POLE_H, Vector3(0.0, FLAG_POLE_H * 0.5, 0.0), IRON, Vector3.ZERO, 6))
	var fy: float = FLAG_POLE_H - 0.6
	p.append(GroundKit.box_part(Vector3(1.5, 0.95, 0.02), Vector3(0.8, fy, 0.0), FLAG_RED, Vector3.ZERO, false))
	for s in [-1.0, 1.0]:
		p.append(GroundKit.cyl_part(0.3, 0.3, 0.02, Vector3(0.8, fy, s * 0.012), WHITE, Vector3(90, 0, 0), 14, false))
	return _cached("flag", p)


## A two-wheeled field kitchen (Gulaschkanone): a firebox on a trailer with a boiler and a chimney, a draw bar at -Z.
static func kitchen_mesh() -> ArrayMesh:
	if _cache.has("kitchen"):
		return _cache["kitchen"]
	var p: Array = []
	p.append(GroundKit.box_part(Vector3(1.6, 0.14, 2.6), Vector3(0.0, 0.6, 0.0), BLACK))
	for wx in [-0.95, 0.95]:
		p.append(GroundKit.cyl_part(0.6, 0.6, 0.2, Vector3(wx, 0.6, 0.0), BLACK, Vector3(0, 0, 90), 10))
	p.append(GroundKit.box_part(Vector3(1.4, 0.9, 1.9), Vector3(0.0, 1.15, 0.0), FIELD_GREEN))
	p.append(GroundKit.cyl_part(0.45, 0.45, 1.5, Vector3(0.0, 1.45, -0.1), IRON, Vector3(90, 0, 0), 10))
	p.append(GroundKit.cyl_part(0.12, 0.12, 1.2, Vector3(0.0, 2.5, 0.55), IRON, Vector3.ZERO, 8))
	p.append(GroundKit.box_part(Vector3(0.1, 0.1, 1.6), Vector3(0.0, 0.6, -2.0), BLACK, Vector3.ZERO, false))
	return _cached("kitchen", p)


static func _vertex_material() -> StandardMaterial3D:
	if _vcol_mat == null:
		_vcol_mat = StandardMaterial3D.new()
		_vcol_mat.vertex_color_use_as_albedo = true
		_vcol_mat.roughness = 1.0
	return _vcol_mat


# ------------------------------------------------------------------ people

## The 2-3 firemen by a fire engine at `stop` (dark ARP outfit, 12-entry figures as WarReactions uses).
static func fire_crew(stop: Vector3, rng: RandomNumberGenerator) -> Array:
	var men: Array = []
	var n: int = 2 + rng.randi() % 2
	for k in n:
		var a: float = rng.randf() * TAU
		var p: Vector3 = stop + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.6, 4.0)
		p.y = GroundKit.ground_y(p.x, p.z)
		var face: Vector3 = stop - p
		face.y = 0.0
		var kind: int = AirfieldPeople.Kind.TALK if k % 2 == 0 else AirfieldPeople.Kind.SMOKER
		men.append([p, face.normalized() if face.length() > 0.01 else Vector3.FORWARD, kind, 0.0, -1.0, 0.0, false, null, 0.0, p.y, p.y, AirfieldPeople.CIV_ARP])
	return men


static func _dry(p: Vector3) -> bool:
	if GroundKit.is_water(p.x, p.z):
		return false
	var gy: float = GroundKit.ground_y(p.x, p.z)
	return Obstacles.hit(Vector3(p.x, gy, p.z), 0.9, gy + 0.3, gy + 2.0).is_empty()


## Two German sentries on the landward side of an Axis-held harbour, facing inland, and their MultiMesh.
static func harbour_sentries(container: Node3D, centre: Vector3, team: String, key: String, seed_v: int) -> MultiMeshInstance3D:
	if not harbour_guarded(team, key):
		return null
	var sea: Vector3 = GroundKit.water_dir(centre, 260.0)
	sea.y = 0.0
	if sea.length() < 0.1:
		return null
	sea = sea.normalized()
	var side := Vector3(-sea.z, 0.0, sea.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var men: Array = []
	for s in [-1.0, 1.0]:
		var p: Vector3 = centre - sea * rng.randf_range(9.0, 12.0) + side * s * 3.2
		p.y = 0.0
		if not _dry(p):
			continue
		men.append([p, -sea, AirfieldPeople.Kind.SALUTE, 0.0, -1.0, 0.0, true])
	if men.is_empty():
		return null
	var origin := Vector3(centre.x, GroundKit.ground_y(centre.x, centre.z), centre.z)
	var mi: MultiMeshInstance3D = AirfieldPeople.spawn(container, men, origin, team, seed_v + 3, "", true)
	if mi != null:
		mi.name = "HarbourSentries"
	return mi


## The Kommandantur flag on the roof of an Axis-held town hall (see flag_flown). Returns the node or null.
static func kommandantur_flag(container: Node3D, d: Dictionary, team: String, size: int) -> MeshInstance3D:
	var civic: Array = d.get("civic", [])
	if not flag_flown(team, size, civic):
		return null
	for cv in civic:
		var cd: Dictionary = cv
		if str(cd.get("kind", "")) != "townhall" or not cd.has("pos"):
			continue
		var cp: Vector3 = cd["pos"]
		var sc: float = float(cd.get("scale", 1.0))
		var mi := MeshInstance3D.new()
		mi.name = "KommandanturFlag"
		mi.mesh = flag_mesh()
		mi.position = Vector3(cp.x, cp.y + TOWN_HALL_TOP * sc, cp.z)
		mi.scale = Vector3.ONE * 1.6                  # a bigger flag: it has to read from the street and from the air
		mi.visibility_range_end = 2500.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		container.add_child(mi)
		print("[kommandantur] flag over the town hall at %.0f,%.0f, pole top %.1f m" % [cp.x, cp.z, mi.position.y])
		return mi
	return null


## The Axis field's kitchen and wagons. `g` is the airfield's AirfieldPeople.Grid, `ok` the populate's free test (a
## Vector3 -> bool Callable). Adds the mesh nodes to `container` and returns the men as populate's extra entries.
static func airfield_camp(container: Node3D, g, ok: Callable, centre: Vector3, half: float, y: float, team: String, seed_v: int) -> Array:
	var men: Array = []
	if not camp_allowed(team):
		return men
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# the kitchen: a footprint of about 6 m that the Grid says is clear
	var c := Vector3.ZERO
	var f := Vector3.FORWARD
	var placed: bool = false
	for tries in 40:
		var a: float = rng.randf() * TAU
		var cc: Vector3 = centre + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.25, 0.6) * half
		cc.y = 0.0
		var fa: float = rng.randf() * TAU
		var ff := Vector3(cos(fa), 0.0, sin(fa))
		var sd := Vector3(-ff.z, 0.0, ff.x)
		var clear: bool = true
		for q in [Vector3.ZERO, ff * 2.5, -ff * 2.5, sd * 2.5, -sd * 2.5, ff * 5.0]:
			if not ok.call(cc + q):
				clear = false
				break
		if clear:
			c = cc
			f = ff
			placed = true
			break
	if not placed:
		return men
	var ll: Vector2 = WorldCoords.world_to_latlon(c)
	print("[kitchen] Axis field kitchen at %.5f, %.5f (lat, lon)" % [ll.x, ll.y])
	_node(container, kitchen_mesh(), Transform3D(Basis.looking_at(f, Vector3.UP).scaled(Vector3.ONE * AirfieldPeople.SCALE), Vector3(c.x, y + 0.02, c.z)))
	# 4-6 men round it: most sit, one smokes, one talks
	var n_men: int = 4 + rng.randi() % 3
	var a0: float = rng.randf() * TAU
	for k in n_men:
		var b: float = a0 + TAU * float(k) / float(n_men)
		var dir := Vector3(cos(b), 0.0, sin(b))
		var p: Vector3 = c + dir * rng.randf_range(2.2, 2.8)
		p.y = 0.0
		if not ok.call(p):
			continue
		var kind: int = AirfieldPeople.Kind.SIT
		if k % 3 == 1:
			kind = AirfieldPeople.Kind.SMOKER
		elif k % 3 == 2:
			kind = AirfieldPeople.Kind.TALK
		men.append([p, -dir, kind, 0.0, -1.0, 0.0, true])
	g.mark_disc(c, 4.0)             # (after the men: they stand inside that disc, and the Grid would turn them away)
	# one or two horse-drawn supply wagons at the field edge: the led horse and cart from FarmPeople, as still meshes
	var nw: int = 1 + rng.randi() % 2
	for w in nw:
		for tries2 in 30:
			var wa: float = rng.randf() * TAU
			var p0: Vector3 = centre + Vector3(cos(wa), 0.0, sin(wa)) * rng.randf_range(0.75, 0.9) * half
			p0.y = 0.0
			var wd := Vector3(cos(wa + rng.randf_range(-0.6, 0.6)), 0.0, sin(wa + rng.randf_range(-0.6, 0.6)))
			var p1: Vector3 = p0 - wd * 3.8
			p1.y = 0.0
			if not (ok.call(p0) and ok.call(p1) and ok.call((p0 + p1) * 0.5) and g.line_free(p0, p1)):
				continue
			g.mark_line(p0, p1, 1.8)
			var wxf := Transform3D(Basis.looking_at(wd, Vector3.UP).scaled(Vector3.ONE * AirfieldPeople.MAN), Vector3(p0.x, y + 0.02, p0.z))   # (the farm props are authored in figure metres: FarmPeople scales them by MAN)
			var wmi: MeshInstance3D = _node(container, FarmPeople.prop_mesh(FarmPeople.Prop.CART_LED), wxf)
			wmi.material_override = _vertex_material()
			var wll: Vector2 = WorldCoords.world_to_latlon(p0)
			print("[wagon] Axis supply wagon at %.5f, %.5f (lat, lon)" % [wll.x, wll.y])
			# a soldier at the horse's head
			var side := Vector3(-wd.z, 0.0, wd.x)
			var hp: Vector3 = p0 + side * 1.2
			hp.y = 0.0
			if ok.call(hp):
				men.append([hp, -side, AirfieldPeople.Kind.TALK, 0.0, -1.0, 0.0, true])
			break
	return men


static func _node(container: Node3D, mesh: Mesh, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "WarProp"
	mi.mesh = mesh
	mi.transform = xf
	mi.visibility_range_end = 2500.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	container.add_child(mi)
	return mi
