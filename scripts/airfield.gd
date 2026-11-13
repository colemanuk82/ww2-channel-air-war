class_name Airfield
extends Node3D
## WW2-style airfield: a main runway plus a crosswind runway, a perimeter taxiway, dispersal pens
## with earth revetments, hangars, a control tower and a wind sock. The node is rotated so local -Z
## runs along the take-off heading; the surface sits at local y = 0. Gameplay uses the main runway.


@export var airfield_name: String = "Airfield"
@export var runway_length: float = 1000.0
@export var runway_width: float = 56.0     # wide enough for a pair taking off side by side (aircraft are ~1.45x scale)
var heading_deg: float = 0.0
var surface_y: float = 0.0
var team: String = ""          # "Allies" / "Axis" allegiance of the field
var lights_active: bool = true # at night the flare path / runway lamps show only while the field is active
var style: String = "triangle"  # "triangle", "grass", "cross", "parallel", "forward", "raf_grass", "lw_field",
	# "raf_bomber", "raf_fighter", "raf_satellite", "night_fighter", "lw_fliegerhorst", "usaf_alg", "glider_strip"

const GRASS_IDS := []
## Pre-war RAF grass stations as they were in 1940: no paved runway, an arc of big hangars behind a concrete apron,
## E-type blast pens round a perimeter track, boundary markers and the landing T.
const RAF_GRASS_IDS := ["hawkinge", "hornchurch", "debden", "kenley", "north_weald", "gravesend", "rochford", "west_malling",
	"detling", "eastchurch", "croydon", "redhill", "martlesham_heath", "middle_wallop", "warmwell", "ford", "thorney_island",
	"shoreham", "friston", "biggin_hill"]
## Luftwaffe forward grass fields in the Pas-de-Calais and Normandy, 1940-41: a rolled grass strip, aircraft dispersed
## round the field edge under camouflage nets, tents and lorries instead of hangars.
const LW_FIELD_IDS := ["marck", "st_omer", "calais_marck", "saint_omer", "merville", "saint_inglevert", "guines", "coquelles", "audembert",
	"desvres", "monchy_breton", "vitry_en_artois", "abbeville_drucat", "beauvais_tille", "cormeilles_en_vexin"]
## Layouts: "triangle" (three paved runways), "grass" (dirt strip + apron), "cross" (two crossing paved runways),
## "parallel" (two parallel runways + terminal apron) and "forward" (steel-mesh strip with tented dispersals).
const CROSS_IDS := ["eindhoven", "schiphol", "gilze_rijen", "volkel", "venlo", "twente", "hopsten", "rheine", "woensdrecht",
	"brussels_melsbroek", "koln_butzweilerhof", "dusseldorf_lohausen", "essen_mulheim", "soesterberg", "deelen", "wittering",
	"cottesmore", "ypenburg", "valkenburg", "aachen_merzbruck", "bonn_hangelar", "cranfield", "tempsford"]
const PARALLEL_IDS := ["frankfurt_rhein_main", "wiesbaden_erbenheim", "koln_wahn", "florennes", "chievres", "gutersloh",
	"lyneham", "brize_norton", "benson", "abingdon", "cosford", "northolt", "duxford"]
const FORWARD_IDS := ["brussels_evere", "antwerp_deurne", "le_culot", "diest", "asch", "grimbergen", "st_trond",
	"rotterdam_waalhaven", "bicester", "silverstone", "gaydon", "lympne", "cap_gris_nez"]


## Which layout an airfield gets: real fields use a layout that suits them, others a mix by id hash.
static func style_for(id: String) -> String:
	if id in RAF_GRASS_IDS:
		return "raf_grass"
	if id in LW_FIELD_IDS:
		return "lw_field"
	if id in GRASS_IDS:
		return "grass"
	if id in CROSS_IDS:
		return "cross"
	if id in PARALLEL_IDS:
		return "parallel"
	if id in FORWARD_IDS or id.begins_with("af_"):
		return "forward"
	if id == "manston":
		return "triangle"
	return ["triangle", "grass", "cross", "parallel", "forward"][absi(hash(id)) % 5]


## Style strings a record may declare in data/locations.json ("style": "..."). Anything else falls back
## to the id-list / hash layout above.
const STYLE_KEYS := ["raf_bomber", "raf_fighter", "raf_satellite", "night_fighter", "lw_fliegerhorst",
	"lw_field", "usaf_alg", "glider_strip"]


## Which layout an airfield gets, with the record's own say and the war date taken into account:
##  1. an explicit "style" key in the locations.json record wins (unknown values are ignored),
##  2. era rules: the RAF fighter stations lay concrete runways and E-pens from the invasion build-up on,
##     and the af_* forward strips become American advanced landing grounds for the same period,
##  3. otherwise the plain id-list / hash choice of style_for().
static func style_for_record(id: String, rec: Dictionary) -> String:
	var declared: String = str(rec.get("style", ""))
	if declared in STYLE_KEYS:
		return declared
	var base: String = style_for(id)
	var late: bool = EraClock.band() in ["buildup", "liberation", "1945"]
	if base == "raf_grass" and late:
		return "raf_fighter"
	if base == "forward" and id.begins_with("af_") and late:
		return "usaf_alg"
	return base


## Footprint (radius in world units) that scenery / trees must keep clear of.
var clear_radius: float = 1900.0

var _asphalt: Material
var _asphalt2: Material
var _white: Material
var _dispersal_local: Array = []      # Vector3 local positions of the dispersal pens
var markers_local: Array = []         # Transform3D: grass-field boundary markers (dressed by the populator)
var pens_local: Array = []            # Transform3D: E-type blast pens (raf_grass)
var nets_local: Array = []            # Transform3D: camouflage nets over dispersed aircraft (lw_field)


static func create(p_name: String, world_pos: Vector3, p_heading_deg: float, ground_y: float) -> Airfield:
	var a := Airfield.new()
	a.airfield_name = p_name
	a.heading_deg = p_heading_deg
	a.surface_y = ground_y
	a.position = Vector3(world_pos.x, ground_y, world_pos.z)
	a.rotation.y = -deg_to_rad(p_heading_deg)
	return a


## World position of the runway threshold (take-off start), slightly in.
func get_threshold_position() -> Vector3:
	var dir: Vector3 = WorldCoords.heading_to_dir(heading_deg)
	return Vector3(position.x, surface_y, position.z) - dir * (runway_length * 0.5 - 22.0)


## Layout multiplier relative to the original 420 m design (taxiways, pens, buildings scale with it).
func layout_scale() -> float:
	return runway_length / 420.0


func _ready() -> void:
	build_layout()


var _built: bool = false


## Build the runways, taxiways and pads. Called from _ready, but WorldPopulator calls it straight after create()
## so the layout (dispersal pads, footprint) exists while the field is dressed - streamed fields are dressed
## before they enter the scene tree.
func build_layout() -> void:
	if _built:
		return
	_built = true
	var k: float = layout_scale()
	name = airfield_name.replace(" ", "")
	# aged concrete and tarmac (toon detail 6) and worn paint (detail 7): see shaders/toon.gdshader
	_asphalt = ToonUtil.make_toon(Color(0.40, 0.40, 0.38), {"outline": false, "detail": 6, "rim": 0.05})
	_asphalt2 = ToonUtil.make_toon(Color(0.43, 0.42, 0.40), {"outline": false, "detail": 6, "rim": 0.05})
	_white = ToonUtil.make_toon(Color(0.74, 0.73, 0.68), {"outline": false, "rim": 0.0, "detail": 7})
	var grass_pad: Material = ToonUtil.make_toon(Color(0.30, 0.38, 0.18), {"outline": false, "tex": "grass"})
	var earth: Material = ToonUtil.make_toon(Color(0.34, 0.28, 0.19), {"outline": false, "tex": "gravel"})

	# flattened grass airfield apron
	# (the old bright grass slab is gone: the terrain shader tints the airfield grass and blends it into the fields)

	match style:
		"grass":
			_build_grass(earth)
		"cross":
			_build_cross(earth)
		"parallel":
			_build_parallel(earth)
		"forward", "usaf_alg":
			_build_forward(earth)
		"raf_grass":
			_build_raf_grass(earth)
		"lw_field":
			_build_lw_field(earth)
		"raf_bomber":
			_build_raf_bomber(earth)
		"raf_fighter", "night_fighter", "lw_fliegerhorst":
			_build_triangle(earth)
		"raf_satellite", "glider_strip":
			_build_grass(earth)
		_:
			_build_triangle(earth)

	# wind sock
	var pole := ToonUtil.make_mesh(CylinderMesh.new(), Color(0.85, 0.85, 0.85), {"outline": false})
	(pole.mesh as CylinderMesh).top_radius = 0.2
	(pole.mesh as CylinderMesh).bottom_radius = 0.25
	(pole.mesh as CylinderMesh).height = 9.0
	pole.position = Vector3(-runway_width * 0.5 - 40.0, 4.5, -160.0)
	add_child(pole)
	# the sock itself swings with the real wind (scripts/ground/wind_sock.gd)
	var sock := WindSock.new()
	sock.position = Vector3(-runway_width * 0.5 - 40.0, 8.8, -160.0)
	add_child(sock)
	_build_night_lights()
	_build_puddles()


## One paved runway with centre dashes and threshold bars, built on a pivot rotated by angle_deg.
func _runway_pivot(angle_deg: float, length: float, width: float, slab_mat: Material, at: Vector3 = Vector3.ZERO) -> void:
	var rw := Node3D.new()
	rw.position = at
	rw.rotation.y = deg_to_rad(angle_deg)
	add_child(rw)
	var rdir := Vector3(sin(rw.rotation.y), 0.0, cos(rw.rotation.y)) * length * 0.5
	_paved.append([at - rdir, at + rdir, width * 0.5])
	_add_box(rw, Vector3(width, 0.6, length), Vector3(0, 0.0, 0), slab_mat)
	# dim blacked-out runway lights: two edge rows (low amber-white), a red pair at each end
	var nl_: int = int(length / 55.0)
	for li in nl_ + 1:
		var lz: float = -length * 0.5 + 8.0 + float(li) * (length - 16.0) / float(maxi(nl_, 1))
		for lx in [-width * 0.5 + 0.6, width * 0.5 - 0.6]:
			_night_pts.append(rw.transform * Vector3(lx, 1.1, lz))
			_night_cols.append(Color(1.0, 0.85, 0.55, 0.9))
	for end_ in [-1.0, 1.0]:
		for lx2 in [-width * 0.3, width * 0.3]:
			_night_pts.append(rw.transform * Vector3(lx2, 1.1, end_ * (length * 0.5 + 3.0)))
			_night_cols.append(Color(1.0, 0.2, 0.12, 1.0))
	# shoulder stripes along the edges, centre dashes, threshold bars and number blocks: hand-painted, so
	# never quite straight, even or complete (and worn: toon detail 7)
	_edge_stripes(rw, length, width)
	var n: int = int(length / 48.0)
	for i in n:
		var z: float = -length * 0.5 + 25.0 + float(i) * 48.0
		_paint(rw, Vector3(1.8, 0.05, 24.0), Vector3(0, 0.33, z))
	for end in [-1.0, 1.0]:
		var ez: float = end * (length * 0.5 - 7.0)
		for k in 6:
			var bx: float = -width * 0.5 + width * 0.14 + float(k) * (width * 0.72 / 5.0)
			_paint(rw, Vector3(width * 0.06, 0.05, 22.0), Vector3(bx, 0.33, ez - end * 8.0))
		for k in 3:
			_paint(rw, Vector3(2.4, 0.05, 14.0), Vector3((float(k) - 1.0) * 7.0, 0.33, end * (length * 0.5 - 52.0)))


var _paint_rng: RandomNumberGenerator


## A painted marking laid by hand: a little off in size, position and angle.
func _paint(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	if _paint_rng == null:
		_paint_rng = RandomNumberGenerator.new()
		_paint_rng.seed = hash(airfield_name)
	var r := _paint_rng
	var sz := Vector3(size.x * r.randf_range(0.82, 1.15), size.y, size.z * r.randf_range(0.86, 1.08))
	var at := Vector3(pos.x + r.randf_range(-0.35, 0.35) * maxf(size.x, 1.0) * 0.4, pos.y, pos.z + r.randf_range(-1.2, 1.2))
	_add_box(parent, sz, at, _white, r.randf_range(-0.014, 0.014))


## Edge stripes in uneven lengths with gaps, wandering slightly in and out.
func _edge_stripes(parent: Node3D, length: float, width: float) -> void:
	if _paint_rng == null:
		_paint_rng = RandomNumberGenerator.new()
		_paint_rng.seed = hash(airfield_name)
	for side in [-1.0, 1.0]:
		var z: float = -length * 0.5 + 2.0
		while z < length * 0.5 - 4.0:
			var seg: float = minf(_paint_rng.randf_range(26.0, 58.0), length * 0.5 - 2.0 - z)
			if seg > 3.0 and _paint_rng.randf() > 0.08:          # now and then a stretch is missing altogether
				var x: float = side * (width * 0.5 - 1.2) + _paint_rng.randf_range(-0.3, 0.3)
				_add_box(parent, Vector3(0.9 * _paint_rng.randf_range(0.8, 1.15), 0.05, seg), Vector3(x, 0.33, z + seg * 0.5), _white, _paint_rng.randf_range(-0.006, 0.006))
			z += seg + _paint_rng.randf_range(1.5, 6.0)


func _build_triangle(earth: Material) -> void:
	# Three-runway triangle like the real wartime fields: the main runway (gameplay) is one side, two shorter runways
	# run from its ends to a third corner, a perimeter track loops around the lot, clover-leaf hardstandings sit
	# outside the track, the technical site (T2 hangars, huts, tower) is on the far side.
	var L: float = runway_length
	var v1 := Vector3(0, 0, -L * 0.5)
	var v2 := Vector3(0, 0, L * 0.5)
	var v3 := Vector3(L * 0.62, 0, 0)
	_runway_pivot(0.0, L, runway_width, _asphalt)
	_runway_seg(v2, v3, runway_width * 0.72, _asphalt2)
	_runway_seg(v3, v1, runway_width * 0.72, _asphalt2)

	# perimeter track: triangle outside the runways, joined to the runway ends by short taxi links
	var p1 := Vector3(-L * 0.12, 0, -L * 0.5 - L * 0.13)
	var p2 := Vector3(-L * 0.12, 0, L * 0.5 + L * 0.13)
	var p3 := Vector3(L * 0.62 + L * 0.15, 0, 0)
	var loop: Array = [p1, p2, p3]
	for i in 3:
		var qa: Vector3 = loop[i]
		var qb: Vector3 = loop[(i + 1) % 3]
		_link(qa, qb, 12.0, _asphalt2)
		_box(Vector3(14.0, 0.5, 14.0), Vector3(qa.x, 0.0, qa.z), _asphalt2)
	_link(v1 + Vector3(0, 0, 10.0), Vector3(p1.x, 0, p1.z + 30.0), 14.0, _asphalt2)
	_link(v2 - Vector3(0, 0, 10.0), Vector3(p2.x, 0, p2.z - 30.0), 14.0, _asphalt2)
	_link(Vector3(0, 0, 0), Vector3(p1.x, 0, 0), 14.0, _asphalt2)
	_link(v3 + Vector3(-12.0, 0, 0), Vector3(p3.x, 0, 0), 14.0, _asphalt2)

	# clover-leaf dispersal hardstandings along the two outer sides of the triangle, each with a stem to the track
	var pan_mat: Material = ToonUtil.make_toon(Color(0.36, 0.36, 0.34), {"outline": false, "tex": "concrete"})
	for edge in 2:
		var ea: Vector3 = p2 if edge == 0 else p1
		var eb: Vector3 = p3
		var dirv: Vector3 = (eb - ea).normalized()
		var outward := Vector3(-dirv.z, 0, dirv.x) * (1.0 if edge == 1 else -1.0)
		for i in 6:
			var t: float = (float(i) + 0.6) / 6.2
			var base: Vector3 = ea.lerp(eb, t)
			var hub: Vector3 = base + outward * 85.0
			_link(base, hub, 8.0, _asphalt2)
			_clover(hub, atan2(outward.x, outward.z), pan_mat, earth)
	for i in 3:
		var wz: float = -L * 0.3 + float(i) * L * 0.3
		var hubw := Vector3(p1.x - 85.0, 0, wz)
		_link(Vector3(p1.x, 0, wz), hubw, 8.0, _asphalt2)
		_clover(hubw, PI * 1.5, pan_mat, earth)


## RAF heavy-bomber station: the three-runway triangle plus frying-pan hardstandings round the outer sides
## of the perimeter track (the pans face the bombing circles; the west side stays the technical site).
func _build_raf_bomber(earth: Material) -> void:
	_build_triangle(earth)
	var L: float = runway_length
	var p1 := Vector3(-L * 0.12, 0, -L * 0.5 - L * 0.13)
	var p2 := Vector3(-L * 0.12, 0, L * 0.5 + L * 0.13)
	var p3 := Vector3(L * 0.62 + L * 0.15, 0, 0)
	var pan: Material = ToonUtil.make_toon(Color(0.58, 0.57, 0.54), {"outline": false, "rim": 0.0, "detail": 4})
	_frying_pans([p1, p2, p3], pan, 240.0, Vector2(-L * 0.12, 0.0), L * 0.72)


## RAF fighter station after the 1944 paving (Epsom runways on a fighter field): the triangle geometry plus
## E-type blast pens round the outside of the cloverleaf hardstandings, each opening onto a short stub track.
func _build_raf_fighter(earth: Material) -> void:
	_build_triangle(earth)
	var L: float = runway_length
	var p1 := Vector3(-L * 0.12, 0, -L * 0.5 - L * 0.13)
	var p2 := Vector3(-L * 0.12, 0, L * 0.5 + L * 0.13)
	var p3 := Vector3(L * 0.62 + L * 0.15, 0, 0)
	var loop: Array = [p1, p2, p3]
	for i in 3:
		var a: Vector3 = loop[i]
		var b: Vector3 = loop[(i + 1) % 3]
		if (a as Vector3).x < 0.0 and (b as Vector3).x < 0.0:
			continue                          # the west side is the technical site: hangars and dumps
		for kk in 4:
			var t: float = 0.16 + float(kk) * 0.23      # in the gaps between the cloverleaf stems
			var p: Vector3 = (a as Vector3).lerp(b as Vector3, t)
			var dirv: Vector3 = ((b as Vector3) - (a as Vector3)).normalized()
			var outv := Vector3(-dirv.z, 0.0, dirv.x)
			if outv.dot(p) < 0.0:
				outv = -outv
			var c: Vector3 = p + outv * 150.0           # beyond the cloverleaf lobes, on the grass
			var yaw: float = atan2(outv.x, outv.z) + PI
			pens_local.append(Transform3D(Basis(Vector3.UP, yaw), c))
			_link(p, p + outv * 138.0, 8.0, _asphalt2)
			for bay in [-7.0, 7.0]:
				_dispersal_local.append(c + Basis(Vector3.UP, yaw) * Vector3(bay, 0.0, 2.0))


## Runway edge / threshold lamps for a grass or dirt strip, in the airfield's local frame. Paved runways
## get the same points from _runway_pivot.
func _strip_lamps(half_w: float, length: float) -> void:
	var n: int = int(length / 55.0)
	for li in n + 1:
		var z: float = -length * 0.5 + 8.0 + float(li) * (length - 16.0) / float(maxi(n, 1))
		for lx in [-half_w + 0.8, half_w - 0.8]:
			_night_pts.append(Vector3(lx, 1.1, z))
			_night_cols.append(Color(1.0, 0.85, 0.55, 0.9))
	for end in [-1.0, 1.0]:
		for lx2 in [-half_w * 0.55, half_w * 0.55]:
			_night_pts.append(Vector3(lx2, 1.1, end * (length * 0.5 + 3.0)))
			_night_cols.append(Color(1.0, 0.2, 0.12, 1.0))


## Dirt-strip field: one wide pale gravel/dirt runway, a big dirt apron with a row of arched hangars behind it,
## a taxi strip joining apron and runway, parked aircraft, huts and silos (set dressing is added by the populator).
func _build_grass(earth: Material) -> void:
	var L: float = runway_length
	var dirt: Material = ToonUtil.make_toon(Color(0.40, 0.37, 0.27), {"outline": false, "tex": "gravel"})
	var dirt2: Material = ToonUtil.make_toon(Color(0.57, 0.53, 0.40), {"outline": false, "rim": 0.0, "detail": 4})
	var rut: Material = ToonUtil.make_toon(Color(0.50, 0.46, 0.34), {"outline": false, "rim": 0.0, "detail": 3})
	# the strip itself: wide, no paint, faint wheel ruts; a lighter worn centre keeps it readable at dawn
	_box(Vector3(runway_width * 1.7, 0.5, L), Vector3.ZERO, dirt)
	_box(Vector3(runway_width * 1.12, 0.51, L * 0.97), Vector3(0, -0.005, 0), dirt2)
	_box(Vector3(2.0, 0.55, L * 0.9), Vector3(-runway_width * 0.45, 0.0, 0), rut)
	_box(Vector3(2.0, 0.55, L * 0.9), Vector3(runway_width * 0.45, 0.0, 0), rut)
	_strip_lamps(runway_width * 0.82, L)
	# big apron west of the runway, joined by a wide taxi link and a taxi strip along the strip's edge
	_box(Vector3(210.0, 0.5, 250.0), Vector3(-205.0, 0.0, -90.0), dirt2)
	_link(Vector3(-105.0, 0, -90.0), Vector3(-runway_width * 0.8, 0, -90.0), 40.0, dirt2)
	_link(Vector3(-100.0, 0, -L * 0.42), Vector3(-100.0, 0, L * 0.38), 16.0, dirt2)
	_link(Vector3(-100.0, 0, -L * 0.42), Vector3(-runway_width * 0.8, 0, -L * 0.46), 16.0, dirt2)
	_link(Vector3(-100.0, 0, L * 0.38), Vector3(-runway_width * 0.8, 0, L * 0.46), 16.0, dirt2)
	# dispersal tracks into the grass on the far (east) side, each ending in a small pad
	for i in 6:
		var z: float = -L * 0.38 + float(i) * L * 0.15
		_link(Vector3(runway_width * 0.8, 0, z), Vector3(120.0, 0, z), 10.0, dirt2)
		_box(Vector3(34.0, 0.5, 26.0), Vector3(132.0, 0.0, z), dirt2)
		_dispersal_local.append(Vector3(132.0, 0.0, z))
		_add_box(self, Vector3(4.0, 3.0, 26.0), Vector3(152.0, 1.5, z), earth)
	# parking spots on the apron (the populator parks aircraft here)
	for row in 3:
		for i in 6:
			_dispersal_local.append(Vector3(-150.0 - float(row) * 38.0, 0.0, -190.0 + float(i) * 40.0))


## Two crossing paved runways (main = gameplay) inside an octagonal perimeter track, frying-pan hardstandings
## round the track and a hardstanding apron on the west side - the layout of most 1942-44 bomber and fighter bases.
func _build_cross(earth: Material) -> void:
	var L: float = runway_length
	_runway_pivot(0.0, L, runway_width, _asphalt)
	_runway_pivot(58.0, L * 0.8, runway_width * 0.8, _asphalt2, Vector3(0, 0.15, L * 0.05))
	var hx: float = L * 0.40
	var hz: float = L * 0.58
	var loop: Array = _octagon(hx, hz, L * 0.16, 0.0)
	_track_loop(loop, 13.0, _asphalt2)
	for end in [-1.0, 1.0]:
		_link(Vector3(0, 0, end * (L * 0.5 - 10.0)), Vector3(0, 0, end * hz), 14.0, _asphalt2)
	# the cross runway's ends join the track along its own heading
	var r2: Vector3 = Vector3(sin(deg_to_rad(58.0)), 0.0, cos(deg_to_rad(58.0)))
	for end2 in [-1.0, 1.0]:
		var e: Vector3 = Vector3(0, 0, L * 0.05) + r2 * end2 * (L * 0.4 - 10.0)
		_link(e, _nearest(loop, e), 14.0, _asphalt2)
	var pan: Material = ToonUtil.make_toon(Color(0.58, 0.57, 0.54), {"outline": false, "rim": 0.0, "detail": 4})
	_box(Vector3(190.0, 0.5, 300.0), Vector3(-hx - 110.0, 0.0, -90.0), pan)
	_link(Vector3(-hx, 0, -90.0), Vector3(-hx - 15.0, 0, -90.0), 30.0, _asphalt2)
	for i in 5:
		for r in 2:
			_dispersal_local.append(Vector3(-hx - 60.0 - float(r) * 70.0, 0.0, -210.0 + float(i) * 55.0))
	_frying_pans(loop, pan, 175.0, Vector2(-hx - 20.0, -90.0), 240.0)


## Two parallel paved runways inside a rectangular perimeter track, cross-taxiways between them, a large terminal
## apron on the west and frying-pan hardstandings round the track.
func _build_parallel(earth: Material) -> void:
	var L: float = runway_length
	var sep: float = 330.0 + L * 0.05
	_runway_pivot(0.0, L, runway_width, _asphalt)
	_runway_pivot(0.0, L * 0.85, runway_width * 0.9, _asphalt2, Vector3(sep, 0.15, L * 0.06))
	var mid: float = sep * 0.5
	_link(Vector3(mid, 0, -L * 0.5), Vector3(mid, 0, L * 0.5), 14.0, _asphalt2)
	for z in [-L * 0.45, -L * 0.15, L * 0.15, L * 0.45]:
		_link(Vector3(runway_width * 0.5, 0, z), Vector3(sep - runway_width * 0.5, 0, z), 14.0, _asphalt2)
	var cx: float = sep * 0.5
	var loop: Array = _octagon(sep * 0.5 + 150.0, L * 0.58, 120.0, cx)
	_track_loop(loop, 13.0, _asphalt2)
	_link(Vector3(0, 0, -L * 0.5 + 8.0), Vector3(0, 0, -L * 0.58), 14.0, _asphalt2)
	_link(Vector3(0, 0, L * 0.5 - 8.0), Vector3(0, 0, L * 0.58), 14.0, _asphalt2)
	var pan: Material = ToonUtil.make_toon(Color(0.60, 0.59, 0.56), {"outline": false, "rim": 0.0, "detail": 4})
	var ax: float = cx - (sep * 0.5 + 150.0)
	_box(Vector3(240.0, 0.5, 420.0), Vector3(ax - 130.0, 0.0, -L * 0.1), pan)
	_link(Vector3(ax, 0, -L * 0.1), Vector3(ax - 15.0, 0, -L * 0.1), 30.0, _asphalt2)
	for r in 3:
		for i in 7:
			_dispersal_local.append(Vector3(ax - 70.0 - float(r) * 60.0, 0.0, -L * 0.1 - 170.0 + float(i) * 56.0))
	_frying_pans(loop, pan, 190.0, Vector2(ax - 20.0, -L * 0.1), 260.0)


## The grass landing ground as one surface (shaders/grass_field.gdshader): mown bands, the RAF cross-mown
## direction, a ragged edge into longer grass, wandering wheel ruts and worn patches, faded into the terrain at its
## border. It replaced a stack of thin boxes, whose stepped edges and depth fighting showed as artefacts.
static var _field_shader: Shader


func _grass_surface(L: float, a: Material, b: Material, edge: Material, bare: Material, cross: bool) -> void:
	if _field_shader == null:
		_field_shader = load("res://shaders/grass_field.gdshader")
	var sm := ShaderMaterial.new()
	sm.shader = _field_shader
	var hw: float = runway_width * 1.55
	var hl: float = L * 0.53
	sm.set_shader_parameter("half_w", hw)
	sm.set_shader_parameter("half_l", hl)
	sm.set_shader_parameter("rw", runway_width)
	sm.set_shader_parameter("seed", float(absi(hash(airfield_name)) % 1000))
	sm.set_shader_parameter("col_a", _mat_col(a))
	sm.set_shader_parameter("col_b", _mat_col(b))
	sm.set_shader_parameter("col_edge", _mat_col(edge))
	sm.set_shader_parameter("col_bare", _mat_col(bare))
	sm.set_shader_parameter("cross_on", 1.0 if cross else 0.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw * 2.0, hl * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = sm
	mi.position = Vector3(0.0, 0.07, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "GrassField"
	add_child(mi)


## Base colour of a toon material (the field shader takes the same palette).
func _mat_col(m: Material) -> Color:
	if m is ShaderMaterial:
		var v: Variant = (m as ShaderMaterial).get_shader_parameter("base_color")
		if v is Color:
			return v
		v = (m as ShaderMaterial).get_shader_parameter("albedo")
		if v is Color:
			return v
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color(0.24, 0.31, 0.15)


## Grass blades on the landing ground: clumps of thin swaying blades (shaders/grass_blades.gdshader), short on the
## mown strip and longer along its ragged edge. Laid out in tiles so only the ones near the camera are drawn.
const GRASS_BLADES := false      # off (v3.15): the blade clumps cost too much for what they add
const BLADE_TILE := 120.0
const BLADE_RANGE := 190.0
static var _blade_meshes: Array = []
static var _blade_mat: ShaderMaterial


func _grass_blades(L: float) -> void:
	if not GRASS_BLADES:
		return
	if _blade_meshes.is_empty():
		_blade_mat = ShaderMaterial.new()
		_blade_mat.shader = load("res://shaders/grass_blades.gdshader")
		var mrng := RandomNumberGenerator.new()
		mrng.seed = 7741
		for k in 3:
			_blade_meshes.append(_blade_clump(mrng, 13 + k * 3))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(airfield_name) + 991
	var hw: float = runway_width * 1.5
	var hl: float = L * 0.5
	var nx: int = int(ceil(hw * 2.0 / BLADE_TILE))
	var nz: int = int(ceil(hl * 2.0 / BLADE_TILE))
	for ix in nx:
		for iz in nz:
			var x0: float = -hw + float(ix) * BLADE_TILE
			var z0: float = -hl + float(iz) * BLADE_TILE
			var x1: float = minf(x0 + BLADE_TILE, hw)
			var z1: float = minf(z0 + BLADE_TILE, hl)
			var area: float = (x1 - x0) * (z1 - z0)
			var count: int = int(area / 1.7)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _blade_meshes[(ix + iz) % _blade_meshes.size()]
			mm.instance_count = count
			var buf := PackedFloat32Array()
			buf.resize(count * 12)
			var cx: float = (x0 + x1) * 0.5
			var cz: float = (z0 + z1) * 0.5
			for i in count:
				var x: float = rng.randf_range(x0, x1)
				var z: float = rng.randf_range(z0, z1)
				# mown strip: short; the ragged edge and beyond: longer and denser-looking
				var edge: float = clampf((absf(x) - runway_width * 1.08) / (runway_width * 0.2), 0.0, 1.0)
				var hgt: float = lerpf(rng.randf_range(0.35, 0.6), rng.randf_range(1.0, 1.7), edge)
				var wid: float = rng.randf_range(0.8, 1.3)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wid, hgt, wid))
				var o: int = i * 12
				buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = x - cx
				buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = 0.07
				buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = z - cz
			mm.buffer = buf
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = _blade_mat
			mi.position = Vector3(cx, 0.0, cz)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = BLADE_RANGE
			mi.visibility_range_end_margin = 30.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			add_child(mi)


## One clump: n thin tapering blades leaning out from a common root, darker at the base.
static func _blade_clump(rng: RandomNumberGenerator, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var ang: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.0, 0.28)
		var root := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var lean_a: float = rng.randf() * TAU
		var lean: float = rng.randf_range(0.03, 0.12)
		var hgt: float = rng.randf_range(0.14, 0.30)
		var tip := root + Vector3(cos(lean_a) * lean, hgt, sin(lean_a) * lean)
		var side := Vector3(-sin(lean_a), 0.0, cos(lean_a)) * rng.randf_range(0.010, 0.018)
		var g: float = rng.randf_range(0.85, 1.15)
		var base_c := Color(0.16 * g, 0.22 * g, 0.09 * g, 0.0)
		var tip_c := Color(0.33 * g, 0.41 * g, 0.18 * g, 1.0)
		st.set_color(base_c); st.add_vertex(root - side)
		st.set_color(base_c); st.add_vertex(root + side)
		st.set_color(tip_c); st.add_vertex(tip)
	st.generate_normals()
	return st.commit()


## Scatter thin ground patches as one MultiMesh per material: cheap, and the irregular shapes break up the
## straight mown strip instead of adding dozens of individual draw calls.
func _patch_mm(mat: Material, patches: Array) -> void:
	if patches.is_empty():
		return
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = patches.size()
	mm.mesh = bm
	for i in patches.size():
		var p: Dictionary = patches[i]
		var pos: Vector3 = p["pos"]
		var basis := Basis(Vector3.UP, float(p.get("yaw", 0.0))).scaled(Vector3(float(p["w"]), float(p.get("h", 0.012)), float(p["l"])))
		mm.set_instance_transform(i, Transform3D(basis, pos))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 2400.0
	add_child(mi)


## Pre-war RAF grass station (Biggin Hill, Hornchurch, Kenley... in 1940): no paved runway - a mown landing area
## inside boundary markers - with a concrete apron and an arc of big hangars on the west side, a tarmac perimeter
## track, and E-type blast pens round it, each pen holding two fighters.
func _build_raf_grass(earth: Material) -> void:
	var L: float = runway_length
	# the heavily used landing area has gone to dust, with a ragged grass ring blending into the fields; one
	# shaded surface, real grass blades grow on it close up - see _grass_surface / _grass_blades
	var mown: Material = ToonUtil.make_toon(Color(0.40, 0.36, 0.26), {"outline": false, "detail": 4, "patch": Color(0.34, 0.30, 0.21), "patch_amount": 0.22, "patch_scale": 1.1})
	var mown2: Material = ToonUtil.make_toon(Color(0.35, 0.31, 0.22), {"outline": false, "detail": 4, "patch": Color(0.31, 0.27, 0.19), "patch_amount": 0.18, "patch_scale": 1.3})
	var mown_edge: Material = ToonUtil.make_toon(Color(0.285, 0.335, 0.17), {"outline": false, "detail": 4})
	var bare: Material = ToonUtil.make_toon(Color(0.30, 0.265, 0.185), {"outline": false, "detail": 4, "patch": Color(0.24, 0.23, 0.14), "patch_amount": 0.38, "patch_scale": 1.8})
	_grass_surface(L, mown, mown2, mown_edge, bare, true)
	_strip_lamps(runway_width * 1.12, L)
	_grass_blades(L)
	# perimeter track: an ellipse of tarmac round the landing ground
	# sized so the track and pens stay inside the terrain's flattened zone (~1 km radius)
	var rx: float = L * 0.38
	var rz: float = L * 0.5 + 45.0
	var loop: Array = []
	for i in 24:
		var a: float = TAU * float(i) / 24.0
		loop.append(Vector3(sin(a) * rx, 0.0, cos(a) * rz))
	_track_loop(loop, 11.0, _asphalt2)
	# concrete apron in front of the hangar arc (west)
	var pan: Material = ToonUtil.make_toon(Color(0.42, 0.42, 0.40), {"outline": false, "rim": 0.0, "detail": 4})
	_box(Vector3(110.0, 0.5, 400.0), Vector3(-rx - 60.0, 0.0, -40.0), pan)
	_link(Vector3(-rx, 0, -40.0), Vector3(-rx - 10.0, 0, -40.0), 40.0, _asphalt2)
	for i in 6:
		_dispersal_local.append(Vector3(-rx - 45.0 - float(i % 2) * 36.0, 0.0, -200.0 + float(i) * 68.0))
	# E-type pens round the north, east and south of the track, opening onto it
	for i in 24:
		if i % 2 == 1:
			continue
		var a2: float = TAU * (float(i) + 0.5) / 24.0
		var pt := Vector3(sin(a2) * rx, 0.0, cos(a2) * rz)
		if pt.x < -rx * 0.55:
			continue                       # the west side is the apron and technical site
		var outv: Vector3 = Vector3(sin(a2) / rx, 0.0, cos(a2) / rz).normalized()
		var c: Vector3 = pt + outv * 40.0
		var yaw: float = atan2(outv.x, outv.z) + PI
		pens_local.append(Transform3D(Basis(Vector3.UP, yaw), c))
		_link(pt, pt + outv * 26.0, 8.0, _asphalt2)
		for bay in [-7.0, 7.0]:
			_dispersal_local.append(c + Basis(Vector3.UP, yaw) * Vector3(bay, 0.0, 2.0))
	# boundary markers round the landing ground
	for j in 28:
		var a3: float = TAU * float(j) / 28.0
		markers_local.append(Transform3D(Basis(Vector3.UP, a3), Vector3(sin(a3) * (rx - 30.0), 0.0, cos(a3) * (rz - 30.0))))


## Luftwaffe forward grass field (Pas-de-Calais / Normandy, 1940-41): a rolled grass strip with worn wheel tracks,
## aircraft dispersed round the field edge under camouflage nets on worn earth pads, joined by dirt tracks.
func _build_lw_field(earth: Material) -> void:
	var L: float = runway_length
	# the strip is rolled bare earth with dust bands; grass takes the ragged edge - one shaded surface
	var rolled: Material = ToonUtil.make_toon(Color(0.40, 0.36, 0.26), {"outline": false, "detail": 4, "patch": Color(0.34, 0.30, 0.21), "patch_amount": 0.24, "patch_scale": 1.2})
	var worn: Material = ToonUtil.make_toon(Color(0.30, 0.265, 0.185), {"outline": false, "detail": 4, "patch": Color(0.26, 0.25, 0.15), "patch_amount": 0.30, "patch_scale": 1.6})
	var mown2: Material = ToonUtil.make_toon(Color(0.35, 0.31, 0.22), {"outline": false, "detail": 4, "patch": Color(0.32, 0.28, 0.19), "patch_amount": 0.20, "patch_scale": 1.4})
	var edge: Material = ToonUtil.make_toon(Color(0.285, 0.335, 0.17), {"outline": false, "detail": 4})
	# rolled bands, ragged edge, wandering ruts and worn patches: one shaded surface plus grass blades close up
	_grass_surface(L, rolled, mown2, edge, worn, false)
	_strip_lamps(runway_width * 0.95, L)
	_grass_blades(L)
	# dispersal pads along both long edges and across the far end, each a worn earth patch under a net
	var ex: float = L * 0.34
	var n: int = int(L / 120.0)
	for side in [-1.0, 1.0]:
		for i in n:
			var z: float = -L * 0.44 + float(i) * (L * 0.88 / float(maxi(n - 1, 1)))
			var pp := Vector3(side * (ex + float(i % 3) * 12.0), 0.0, z)
			_pad(pp, 15.0, worn)
			_dispersal_local.append(pp)
			nets_local.append(Transform3D(Basis(Vector3.UP, side * PI * 0.5), pp))
			if i % 2 == 0:
				_link(pp - Vector3(side * 14.0, 0, 0), Vector3(side * runway_width, 0, z), 6.0, worn)
	for k in 4:
		var pe := Vector3(-ex * 0.6 + float(k) * ex * 0.4, 0.0, L * 0.5 + 60.0)
		_pad(pe, 15.0, worn)
		_dispersal_local.append(pe)
		nets_local.append(Transform3D(Basis(), pe))
	for j in 24:
		var t: float = float(j) / 24.0
		var zz: float = -L * 0.5 + L * t
		for sx in [-1.0, 1.0]:
			if j % 3 == 0:
				markers_local.append(Transform3D(Basis(), Vector3(sx * runway_width * 1.1, 0.0, zz)))


func _pad(at: Vector3, r: float, mat: Material) -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.5
	cm.radial_segments = 12
	cm.rings = 1
	pad.mesh = cm
	pad.material_override = mat
	pad.position = at
	add_child(pad)
	_paved.append([at, at, r])


## Octagon of track corners (local), half sizes hx/hz, corners cut by ch, centred on x = cx.
func _octagon(hx: float, hz: float, ch: float, cx: float) -> Array:
	return [Vector3(cx - hx + ch, 0, -hz), Vector3(cx + hx - ch, 0, -hz), Vector3(cx + hx, 0, -hz + ch), Vector3(cx + hx, 0, hz - ch),
		Vector3(cx + hx - ch, 0, hz), Vector3(cx - hx + ch, 0, hz), Vector3(cx - hx, 0, hz - ch), Vector3(cx - hx, 0, -hz + ch)]


## Closed perimeter track through the points, with a round pad at every bend so the joints read as curves.
func _track_loop(pts: Array, w: float, mat: Material) -> void:
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		_link(a, b, w, mat)
		_pad(Vector3(a.x, -0.05, a.z), w * 0.62, mat)


func _nearest(pts: Array, p: Vector3) -> Vector3:
	var best: Vector3 = pts[0]
	for q in pts:
		if (q as Vector3).distance_to(p) < best.distance_to(p):
			best = q
	return best


## Frying-pan hardstandings (circular pads on short stems) every `spacing` m round the track, facing outward,
## except within `skip_r` of the apron at `skip_at`.
func _frying_pans(loop: Array, mat: Material, spacing: float, skip_at: Vector2, skip_r: float) -> void:
	var c := Vector3.ZERO
	for q in loop:
		c += q
	c /= float(loop.size())
	for i in loop.size():
		var a: Vector3 = loop[i]
		var b: Vector3 = loop[(i + 1) % loop.size()]
		var seg: float = a.distance_to(b)
		var n: int = int(seg / spacing)
		for k in n:
			var p: Vector3 = a.lerp(b, (float(k) + 0.5) / float(n))
			if Vector2(p.x - skip_at.x, p.z - skip_at.y).length() < skip_r:
				continue
			var dirv: Vector3 = (b - a).normalized()
			var outv := Vector3(-dirv.z, 0.0, dirv.x)
			if outv.dot(p - c) < 0.0:
				outv = -outv
			var hub: Vector3 = p + outv * 46.0
			_link(p, hub, 8.0, mat)
			_pad(hub, 17.0, mat)
			_dispersal_local.append(hub)


## Advanced landing ground: one steel-mesh strip, a taxi track along it and small dispersal pads in the grass.
func _build_forward(earth: Material) -> void:
	var L: float = runway_length
	var psp: Material = ToonUtil.make_toon(Color(0.45, 0.47, 0.42), {"outline": false, "rim": 0.0, "detail": 3})
	var track: Material = ToonUtil.make_toon(Color(0.50, 0.46, 0.34), {"outline": false, "rim": 0.0, "detail": 4})
	_box(Vector3(runway_width * 0.9, 0.5, L), Vector3.ZERO, psp)
	_box(Vector3(1.4, 0.55, L * 0.92), Vector3(0, 0.0, 0), _white)
	for end in [-1.0, 1.0]:
		_box(Vector3(runway_width * 0.7, 0.55, 3.0), Vector3(0, 0.0, end * (L * 0.5 - 6.0)), _white)
	_link(Vector3(-70.0, 0, -L * 0.45), Vector3(-70.0, 0, L * 0.45), 10.0, track)
	for i in 8:
		var z: float = -L * 0.4 + float(i) * L * 0.115
		_link(Vector3(-runway_width * 0.45, 0, z), Vector3(-70.0, 0, z), 8.0, track)
		_link(Vector3(-70.0, 0, z), Vector3(-120.0, 0, z), 8.0, track)
		_box(Vector3(30.0, 0.5, 24.0), Vector3(-135.0, 0.0, z), track)
		_dispersal_local.append(Vector3(-135.0, 0.0, z))
		_add_box(self, Vector3(3.0, 2.0, 22.0), Vector3(-157.0, 1.0, z), earth)
	for i in 4:
		var z2: float = -L * 0.3 + float(i) * L * 0.2
		_dispersal_local.append(Vector3(55.0, 0.0, z2))


## A runway between two local points (built on a pivot at its midpoint).
func _runway_seg(from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var d: Vector3 = to - from
	var rw := Node3D.new()
	rw.position = (from + to) * 0.5 + Vector3(0.0, 0.15, 0.0)     # raised so it never z-fights with the main runway
	rw.rotation.y = atan2(d.x, d.z)
	add_child(rw)
	var length: float = d.length()
	_paved.append([from, to, width * 0.5])
	_add_box(rw, Vector3(width, 0.6, length), Vector3.ZERO, mat)
	_edge_stripes(rw, length, width)
	var n: int = int(length / 48.0)
	for i in n:
		_paint(rw, Vector3(1.4, 0.05, 20.0), Vector3(0, 0.33, -length * 0.5 + 25.0 + float(i) * 48.0))


## Three-lobed clover-leaf hardstanding with earth blast walls between the lobes; each lobe takes one aircraft.
func _clover(hub: Vector3, ang: float, mat: Material, earth: Material) -> void:
	_box(Vector3(10.0, 0.5, 10.0), hub, mat)
	_paved.append([hub, hub, 7.0])
	for j in 3:
		var a: float = ang + TAU * float(j) / 3.0 + 0.5
		var lp: Vector3 = hub + Vector3(sin(a), 0, cos(a)) * 22.0
		var pad := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 12.0
		cm.bottom_radius = 12.0
		cm.height = 0.5
		cm.radial_segments = 10
		cm.rings = 1
		pad.mesh = cm
		pad.material_override = mat
		pad.position = lp
		add_child(pad)
		_paved.append([lp, lp, 12.0])
		_link(hub, lp, 7.0, mat)
		_dispersal_local.append(Vector3(lp.x, 0.0, lp.z))
		_add_box(self, Vector3(3.5, 3.2, 8.0), hub + Vector3(sin(a + 1.05), 0, cos(a + 1.05)) * 26.0, earth, a + 1.05)


## Ring-shaped perimeter track (rounded rectangle) around the airfield.
func _perimeter_track(mat: Material) -> void:
	var n: int = 110
	var rx: float = 300.0 * layout_scale()
	var rz: float = 250.0 * layout_scale()
	for i in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0) * rx, 0.0, sin(a0) * rz)
		var p1 := Vector3(cos(a1) * rx, 0.0, sin(a1) * rz)
		var mid := (p0 + p1) * 0.5
		var seg := p1 - p0
		_box(Vector3(12.0, 0.5, seg.length() + 2.0), Vector3(mid.x, 0.0, mid.z), mat, atan2(seg.x, seg.z))


## Straight taxiway link between two local points.
var _link_n: int = 0
var _paved: Array = []     # [from, to, half_width] local segments / discs of everything paved (taxiways, pads, runways)


## True if a world point lies within `margin` m of any paved surface of this field (used to keep earth banks,
## props and parked clutter off the taxiways and pads).
func near_paved(world_pos: Vector3, margin: float) -> bool:
	var xf: Transform3D = global_transform if is_inside_tree() else transform
	var p: Vector3 = xf.affine_inverse() * world_pos
	for seg in _paved:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var ab: Vector3 = b - a
		ab.y = 0.0
		var ap: Vector3 = p - a
		ap.y = 0.0
		var t: float = 0.0 if ab.length_squared() < 0.001 else clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
		if (ap - ab * t).length() < float(seg[2]) + margin:
			return true
	return false


func _link(from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var mid := (from + to) * 0.5
	var d := to - from
	_link_n += 1
	_paved.append([from, to, width * 0.5])
	# each taxiway sits a hair below the runways and at its own height, so overlaps never shimmer
	_box(Vector3(width, 0.5, d.length()), Vector3(mid.x, -0.04 - 0.03 * float(_link_n % 3), mid.z), mat, atan2(d.x, d.z))


## Circular tarmac dispersal pen with a low earth revetment around the outboard side.
func _dispersal(pos: Vector3, ang: float, mat: Material, earth: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation.y = ang
	add_child(pivot)
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 22.0
	cm.bottom_radius = 22.0
	cm.height = 0.5
	cm.radial_segments = 12
	cm.rings = 1
	pad.mesh = cm
	pad.material_override = mat
	pad.position = Vector3(0, 0.0, 0)
	pivot.add_child(pad)
	_paved.append([pos, pos, 22.0])
	var r := 29.0
	for i in 7:
		var a: float = PI * (0.5 + float(i) / 6.0)          # outboard arc
		var bx: float = cos(a) * r
		var bz: float = sin(a) * r
		_add_box(pivot, Vector3(4.0, 6.0, 9.0), Vector3(bx, 3.0, bz), earth, -a)


## World positions of the dispersal pens (for parking aircraft off the pavement).
func dispersal_world_points() -> Array:
	# works before the field is in the scene tree too (its parent container sits at the world origin)
	var xf: Transform3D = global_transform if is_inside_tree() else transform
	var out: Array = []
	for p in _dispersal_local:
		out.append(xf * p)
	return out


var _extent: Vector2 = Vector2.ZERO


## Half-extents (local x across, z along the runway) of everything paved, so defences and scenery can sit just
## outside it. Computed once from the built layout.
func footprint_extent() -> Vector2:
	if _extent != Vector2.ZERO:
		return _extent
	build_layout()
	var ex := Vector2(runway_width, runway_length * 0.5)
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != self:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b: AABB = mi.mesh.get_aabb()
		for i in 8:
			var c: Vector3 = t * b.get_endpoint(i)
			ex.x = maxf(ex.x, absf(c.x))
			ex.y = maxf(ex.y, absf(c.z))
	_extent = Vector2(minf(ex.x, runway_length * 0.9), minf(ex.y, runway_length * 0.75))
	return _extent


func _box(size: Vector3, pos: Vector3, mat: Material, yaw: float = 0.0) -> void:
	_add_box(self, size, pos, mat, yaw)


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, yaw: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	if mat == _asphalt or mat == _asphalt2 or mat == _white:
		# a unit box scaled to size: the toon shader reads the strip's width and length from the scale
		mi.mesh = _unit_box(size.y)
		mi.scale = Vector3(size.x, 1.0, size.z)
		if mat == _white:
			# paint marks are 1-4 m wide: sub-pixel beyond a few km, and there are ~100 per runway
			mi.visibility_range_end = 4000.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		# flat grass / earth / patch layers must not cast a little shadow that draws a hard edge
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static var _unit_boxes: Dictionary = {}


## Shared unit-footprint box per height (runway strips and paint marks are scaled copies of it).
static func _unit_box(h: float) -> BoxMesh:
	var key: int = roundi(h * 1000.0)
	if not _unit_boxes.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, h, 1.0)
		_unit_boxes[key] = bm
	return _unit_boxes[key]


var _night_pts: PackedVector3Array = PackedVector3Array()
var _night_cols: PackedColorArray = PackedColorArray()
var _night_lights: MultiMeshInstance3D = null


## One multimesh of soft glow lamps (see shaders/airfield_lamp.gdshader); invisible by day.
func _build_night_lights() -> void:
	if _night_pts.is_empty():
		return
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/airfield_lamp.gdshader") as Shader
	qm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = qm
	mm.instance_count = _night_pts.size()
	for i in _night_pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), _night_pts[i]))
		mm.set_instance_color(i, _night_cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.name = "NightLamps"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	mi.visible = false          # lit only when an aircraft needs them (see _update_lamps)
	add_child(mi)
	_night_lights = mi


## Blackout control: hide the night flare path / runway lamps when the field is not active (occupied fields
## stay dark at night). Safe to call before the lamps are built.
func set_lights_active(v: bool) -> void:
	lights_active = v
	_lamp_t = 0.0
	_update_lamps()


## Cutscenes: light the field regardless of traffic.
var force_lights: bool = false:
	set(v):
		force_lights = v
		_update_lamps()
var _lamp_t: float = 0.0
const LAMP_RADIUS := 3500.0          # aircraft within this (horizontally) ...
const LAMP_HEIGHT := 700.0           # ... and this low over the field (world units, about 350 m) switch them on


## Puddles: a few flat reflective patches that appear when the weather wetness rises.
var _puddles: Array = []
var _puddle_t: float = 0.0
static var _puddle_mat: StandardMaterial3D


func _build_puddles() -> void:
	if _puddle_mat == null:
		_puddle_mat = StandardMaterial3D.new()
		# opaque standing water: a dark, mirror-smooth surface. Opaque so it takes screen-space reflections
		# (transparent surfaces never do) and the sky reflection; it used to be a half-transparent disc that
		# just tinted the runway and showed up as pale blobs.
		_puddle_mat.albedo_color = Color(0.03, 0.04, 0.05)
		_puddle_mat.metallic = 1.0
		_puddle_mat.metallic_specular = 0.6
		_puddle_mat.roughness = 0.02
		_puddle_mat.disable_receive_shadows = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(airfield_name) + 1771
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 14
	cm.rings = 1
	for i in 8:
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _puddle_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(rng.randf_range(-runway_width * 0.75, runway_width * 0.75), 0.085,
			rng.randf_range(-runway_length * 0.42, runway_length * 0.42))
		var rad: float = rng.randf_range(2.0, 7.0)
		mi.scale = Vector3(rad, 1.0, rad * rng.randf_range(0.55, 1.3))
		mi.visible = false
		add_child(mi)
		_puddles.append(mi)


func _update_puddles() -> void:
	var wet: bool = WeatherManager.wetness > 0.12
	for p in _puddles:
		if p is MeshInstance3D and is_instance_valid(p):
			(p as MeshInstance3D).visible = wet
func _process(delta: float) -> void:
	_puddle_t -= delta
	if _puddle_t <= 0.0:
		_puddle_t = 0.5
		_update_puddles()
	if _night_lights == null:
		return
	_lamp_t -= delta
	if _lamp_t > 0.0:
		return
	_lamp_t = 1.0
	_update_lamps()


func _update_lamps() -> void:
	if _night_lights == null or not is_instance_valid(_night_lights) or not is_inside_tree():
		return
	var on: bool = force_lights
	if lights_active and not on:
		var c: Vector3 = global_position
		for n in get_tree().get_nodes_in_group("aircraft"):
			var a: Node3D = n as Node3D
			if a == null or not a.is_inside_tree() or (a is Aircraft and (a as Aircraft).state != Aircraft.State.ALIVE):
				continue
			var p: Vector3 = a.global_position
			if Vector2(p.x - c.x, p.z - c.z).length() < LAMP_RADIUS and p.y - surface_y < LAMP_HEIGHT:
				on = true
				break
	_night_lights.visible = on
