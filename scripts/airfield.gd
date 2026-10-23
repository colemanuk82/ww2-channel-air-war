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
var style: String = "triangle"  # "triangle" (paved three-runway field) or "grass" (dirt strip + big apron, Luftwaffe style)

const GRASS_IDS := ["hawkinge", "marck", "st_omer"]
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

## Footprint (radius in world units) that scenery / trees must keep clear of.
var clear_radius: float = 1900.0

var _asphalt: Material
var _asphalt2: Material
var _white: Material
var _dispersal_local: Array = []      # Vector3 local positions of the dispersal pens


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
		"forward":
			_build_forward(earth)
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


## One paved runway with centre dashes and threshold bars, built on a pivot rotated by angle_deg.
func _runway_pivot(angle_deg: float, length: float, width: float, slab_mat: Material, at: Vector3 = Vector3.ZERO) -> void:
	var rw := Node3D.new()
	rw.position = at
	rw.rotation.y = deg_to_rad(angle_deg)
	add_child(rw)
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


## Dirt-strip field: one wide pale gravel/dirt runway, a big dirt apron with a row of arched hangars behind it,
## a taxi strip joining apron and runway, parked aircraft, huts and silos (set dressing is added by the populator).
func _build_grass(earth: Material) -> void:
	var L: float = runway_length
	var dirt: Material = ToonUtil.make_toon(Color(0.40, 0.37, 0.27), {"outline": false, "tex": "gravel"})
	var dirt2: Material = ToonUtil.make_toon(Color(0.57, 0.53, 0.40), {"outline": false, "rim": 0.0, "detail": 4})
	var rut: Material = ToonUtil.make_toon(Color(0.50, 0.46, 0.34), {"outline": false, "rim": 0.0, "detail": 3})
	# the strip itself: wide, no paint, faint wheel ruts
	_box(Vector3(runway_width * 1.7, 0.5, L), Vector3.ZERO, dirt)
	_box(Vector3(2.0, 0.55, L * 0.9), Vector3(-runway_width * 0.45, 0.0, 0), rut)
	_box(Vector3(2.0, 0.55, L * 0.9), Vector3(runway_width * 0.45, 0.0, 0), rut)
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


## Two crossing paved runways (main = gameplay) with a perimeter taxiway on the west side and a hardstanding apron.
func _build_cross(earth: Material) -> void:
	var L: float = runway_length
	_runway_pivot(0.0, L, runway_width, _asphalt)
	_runway_pivot(58.0, L * 0.8, runway_width * 0.8, _asphalt2, Vector3(0, 0.15, L * 0.05))
	var xw: float = -L * 0.13
	_link(Vector3(xw, 0, -L * 0.5), Vector3(xw, 0, L * 0.5), 14.0, _asphalt2)
	_link(Vector3(-runway_width * 0.5, 0, -L * 0.5 + 12.0), Vector3(xw, 0, -L * 0.5 + 12.0), 14.0, _asphalt2)
	_link(Vector3(-runway_width * 0.5, 0, L * 0.5 - 12.0), Vector3(xw, 0, L * 0.5 - 12.0), 14.0, _asphalt2)
	_link(Vector3(-runway_width * 0.5, 0, 0), Vector3(xw, 0, 0), 14.0, _asphalt2)
	var pan: Material = ToonUtil.make_toon(Color(0.58, 0.57, 0.54), {"outline": false, "rim": 0.0, "detail": 4})
	_box(Vector3(190.0, 0.5, 300.0), Vector3(-L * 0.13 - 110.0, 0.0, -90.0), pan)
	for i in 5:
		for r in 2:
			_dispersal_local.append(Vector3(-L * 0.13 - 60.0 - float(r) * 70.0, 0.0, -210.0 + float(i) * 55.0))
	for i in 5:
		var z: float = -L * 0.38 + float(i) * L * 0.17
		_link(Vector3(runway_width * 0.5, 0, z), Vector3(110.0, 0, z), 9.0, _asphalt2)
		_clover(Vector3(130.0, 0, z), PI * 0.5, pan, earth)
		_dispersal_local.append(Vector3(130.0, 0.0, z))


## Two parallel paved runways joined by cross-taxiways, with a large terminal-style apron on the west side.
func _build_parallel(earth: Material) -> void:
	var L: float = runway_length
	var sep: float = 330.0 + L * 0.05
	_runway_pivot(0.0, L, runway_width, _asphalt)
	_runway_pivot(0.0, L * 0.85, runway_width * 0.9, _asphalt2, Vector3(sep, 0.15, L * 0.06))
	var mid: float = sep * 0.5
	_link(Vector3(mid, 0, -L * 0.5), Vector3(mid, 0, L * 0.5), 14.0, _asphalt2)
	for z in [-L * 0.45, -L * 0.15, L * 0.15, L * 0.45]:
		_link(Vector3(runway_width * 0.5, 0, z), Vector3(sep - runway_width * 0.5, 0, z), 14.0, _asphalt2)
	var pan: Material = ToonUtil.make_toon(Color(0.60, 0.59, 0.56), {"outline": false, "rim": 0.0, "detail": 4})
	_box(Vector3(240.0, 0.5, 420.0), Vector3(-170.0, 0.0, -L * 0.1), pan)
	_link(Vector3(-runway_width * 0.5, 0, -L * 0.1), Vector3(-60.0, 0, -L * 0.1), 30.0, _asphalt2)
	for r in 3:
		for i in 7:
			_dispersal_local.append(Vector3(-110.0 - float(r) * 60.0, 0.0, -L * 0.1 - 170.0 + float(i) * 56.0))


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
	_add_box(rw, Vector3(width, 0.6, length), Vector3.ZERO, mat)
	_edge_stripes(rw, length, width)
	var n: int = int(length / 48.0)
	for i in n:
		_paint(rw, Vector3(1.4, 0.05, 20.0), Vector3(0, 0.33, -length * 0.5 + 25.0 + float(i) * 48.0))


## Three-lobed clover-leaf hardstanding with earth blast walls between the lobes; each lobe takes one aircraft.
func _clover(hub: Vector3, ang: float, mat: Material, earth: Material) -> void:
	_box(Vector3(10.0, 0.5, 10.0), hub, mat)
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


func _link(from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var mid := (from + to) * 0.5
	var d := to - from
	_link_n += 1
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
	var r := 29.0
	for i in 7:
		var a: float = PI * (0.5 + float(i) / 6.0)          # outboard arc
		var bx: float = cos(a) * r
		var bz: float = sin(a) * r
		_add_box(pivot, Vector3(4.0, 6.0, 9.0), Vector3(bx, 3.0, bz), earth, -a)


## World positions of the dispersal pens (for parking aircraft off the pavement).
func dispersal_world_points() -> Array:
	var out: Array = []
	for p in _dispersal_local:
		out.append(to_global(p))
	return out


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
	mi.visible = lights_active
	add_child(mi)
	_night_lights = mi


## Blackout control: hide the night flare path / runway lamps when the field is not active (occupied fields
## stay dark at night). Safe to call before the lamps are built.
func set_lights_active(v: bool) -> void:
	lights_active = v
	if _night_lights != null and is_instance_valid(_night_lights):
		_night_lights.visible = v
