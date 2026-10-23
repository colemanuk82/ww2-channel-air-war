class_name ArmyCampKit
extends RefCounted
## Large army camps beside some airfields: a wired perimeter with a gate and sentry towers, earth tracks, a tank park
## in rows (the front rows under camouflage nets), half-track and lorry lines, a field-gun battery, disruptive-painted
## tent lines and marquees, slit trenches, Nissen huts, sandbagged ammunition bays and fuel-drum dumps behind
## concertina wire, light AA guns, and the old trees left standing between the lines. The terrain shader drops the
## field patchwork under the camp (zone_for, kind 2) and scatter keeps hedges and farms out (CAMP_RADIUS).
## The Allied camps are the 1944 build-up round the south-coast fighter stations and landing grounds
## (Shermans, M3 half-tracks, 25-pounders); the German ones the armour reserve round the Normandy and
## Pas-de-Calais fields (Panzer IVs, Sd.Kfz. 251s, 10.5 cm guns).
##
## Cheap to draw: tents are one MultiMesh per camp; vehicles, guns and buildings are shared merged meshes grouped
## into destructible AirfieldProp clusters; everything fades out with distance (AirfieldProp.VIS_RANGE).

## Fields that always get a camp; about a quarter of the others get one too (by id hash).
const CAMP_IDS := ["tangmere", "westhampnett", "ford", "thorney_island", "hurn", "ibsley", "beaulieu", "christchurch",
	"needs_oar_point", "eastleigh", "middle_wallop", "warmwell", "lympne", "detling", "duxford",
	"caen_carpiquet", "cherbourg_maupertus", "evreux", "rouen_boos", "beauvais_tille", "abbeville_drucat", "merville",
	"saint_omer", "st_omer", "lille_nord", "eindhoven", "venlo"]

const CAMP_RADIUS := 400.0


static func wants_camp(id: String) -> bool:
	return id in CAMP_IDS or absi(hash(id + "camp")) % 4 == 0


## Camp centre (world, y = 0) for an airfield: 2.4-2.8 km out to one side of the runway, on land. Returns
## Vector3.INF when neither side has room (coast, estuary).
static func site_for(id: String, af_pos: Vector3, heading_deg: float) -> Vector3:
	var h: int = absi(hash(id + "campsite"))
	for attempt in 2:
		var side: float = (1.0 if h % 2 == 0 else -1.0) * (1.0 if attempt == 0 else -1.0)
		var hd: float = heading_deg + side * 90.0 + (float(h % 7) - 3.0) * 7.0
		var dir: Vector3 = WorldCoords.heading_to_dir(hd)
		var c: Vector3 = af_pos + dir * (2400.0 + float(h % 5) * 100.0)
		c.y = 0.0
		var ok: bool = GroundKit.raw_y(c.x, c.z) > 1.5
		for k in 4:
			var a: float = TAU * float(k) / 4.0 + 0.4
			var q: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * 320.0
			ok = ok and GroundKit.raw_y(q.x, q.z) > 1.5
		if ok:
			return c
	return Vector3.INF


## Camp half-extents (local x across the runway line, z along it) - the perimeter fence runs round this.
const HX := 295.0
const HZ := 215.0


## Ground-tint zone for the terrain shader (kind 2: worn grass and mud, no field lattice or hedge lines).
static func zone_for(center: Vector3, heading_deg: float) -> Dictionary:
	return {"pos": center, "heading": heading_deg, "half": Vector2(HZ, HX), "feather": 130.0, "kind": 2}


static func build(container: Node3D, center: Vector3, heading_deg: float, team: String, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var yaw: float = -deg_to_rad(heading_deg)
	var axf := Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0.0, center.z))
	var allied: bool = team == "Allies"
	var earth: Color = Color(0.36, 0.31, 0.22)
	if OS.is_debug_build():
		var ll: Vector2 = WorldCoords.world_to_latlon(center)
		print("[camp] %s camp at %.4f, %.4f" % [team, ll.x, ll.y])

	# tracks: a spine from the gate and two cross roads, rutted earth over the worn grass
	var tracks: Array = []
	tracks.append_array(CampAssets.track_xforms(axf, Vector3(0, 0, HZ + 30.0), Vector3(0, 0, -HZ + 30.0), 7.0))
	tracks.append_array(CampAssets.track_xforms(axf, Vector3(-HX + 20.0, 0, -60.0), Vector3(HX - 20.0, 0, -60.0), 6.0))
	tracks.append_array(CampAssets.track_xforms(axf, Vector3(-HX + 20.0, 0, 110.0), Vector3(HX - 20.0, 0, 110.0), 5.0))
	tracks.append_array(CampAssets.track_xforms(axf, Vector3(0, 0, HZ + 30.0), Vector3(0, 0, HZ + 260.0), 6.0))   # out to the lane
	container.add_child(Scatter.multi(Scatter.box_unit(earth.darkened(0.05)), tracks, 5000.0))
	# worn ground under the vehicle parks (one strip per row, following the ground)
	var strips: Array = []
	for r in 3:
		strips.append_array(CampAssets.track_xforms(axf, Vector3(-218.0, 0, -110.0 + float(r) * 17.0), Vector3(-114.0, 0, -110.0 + float(r) * 17.0), 12.0))
		strips.append_array(CampAssets.track_xforms(axf, Vector3(62.0, 0, -110.0 + float(r) * 15.0), Vector3(178.0, 0, -110.0 + float(r) * 15.0), 10.0))
	for r in 2:
		strips.append_array(CampAssets.track_xforms(axf, Vector3(-208.0, 0, -40.0 + float(r) * 14.0), Vector3(-122.0, 0, -40.0 + float(r) * 14.0), 9.0))
	container.add_child(Scatter.multi(Scatter.box_unit(earth), strips, 4500.0))

	# tank park: three rows facing out, as the photos of the 1944 marshalling areas show; the front two rows
	# under camouflage nets on poles
	var tanks: Array = []
	for r in 3:
		for i in 9:
			tanks.append(_w(axf, yaw, Vector3(-210.0 + float(i) * 11.0 + rng.randf_range(-0.8, 0.8), 0.0, -110.0 + float(r) * 17.0), rng.randf_range(-0.04, 0.04)))
	AirfieldFurniture._prop_cluster(container, "tank", AirfieldAssets.tank(team), tanks, team, 4)
	var nets: Array = []
	for k in 4:
		nets.append(_w(axf, yaw, Vector3(-204.0 + float(k) * 22.0, 0.0, -101.5), 0.0))
	for k in 3:
		nets.append(_w(axf, yaw, Vector3(-196.0 + float(k) * 26.0, 0.0, -33.0), 0.0))
	for k in 2:
		nets.append(_w(axf, yaw, Vector3(80.0 + float(k) * 22.0, 0.0, -103.0), 0.0))
	container.add_child(Scatter.multi(AirfieldAssets.camo_net(team), nets, 4500.0))
	# half-track lines
	var hts: Array = []
	for r in 2:
		for i in 8:
			hts.append(_w(axf, yaw, Vector3(-200.0 + float(i) * 10.0, 0.0, -40.0 + float(r) * 14.0), rng.randf_range(-0.05, 0.05)))
	AirfieldFurniture._prop_cluster(container, "truck", AirfieldAssets.halftrack(team), hts, team, 4)
	# lorry park
	var lorries: Array = []
	for r in 3:
		for i in 10:
			lorries.append(_w(axf, yaw, Vector3(70.0 + float(i) * 11.0, 0.0, -110.0 + float(r) * 15.0), rng.randf_range(-0.05, 0.05)))
	AirfieldFurniture._prop_cluster(container, "truck", AirfieldAssets.truck(team), lorries, team, 5)
	# field-gun battery, guns in a line
	var guns: Array = []
	for i in 6:
		guns.append(_w(axf, yaw, Vector3(-200.0 + float(i) * 20.0, 0.0, 40.0), 0.0))
	AirfieldFurniture._prop_cluster(container, "gun", AirfieldAssets.field_gun(team), guns, team, 3)
	# tent lines in disruptive paint (two patch layouts so the rows do not repeat) and marquees
	var tents: Array = [[], []]
	for r in 8:
		for i in 16:
			(tents[(r + i) % 2] as Array).append(_w(axf, yaw, Vector3(30.0 + float(i) * 8.0, 0.0, 10.0 + float(r) * 11.0), rng.randf_range(-0.06, 0.06)))
	for v in 2:
		container.add_child(Scatter.multi(CampAssets.camo_tent(team, v), tents[v], 3200.0))
	var marq: Array = []
	for i in 4:
		marq.append(_w(axf, yaw, Vector3(225.0, 0.0, -10.0 + float(i) * 28.0), 0.0))
	AirfieldFurniture._prop_cluster(container, "hut", AirfieldAssets.marquee(team), marq, team, 2)
	# slit trenches beside the tent lines
	var trenches: Array = []
	for i in 4:
		trenches.append(_w(axf, yaw, Vector3(40.0 + float(i) * 34.0, 0.0, 100.0), 0.0))
	container.add_child(Scatter.multi(CampAssets.slit_trench(), trenches, 2500.0))
	# Nissen huts (cookhouse, stores, orderly room)
	var huts: Array = []
	for i in 6:
		huts.append(_w(axf, yaw, Vector3(-60.0 + float(i) * 22.0, 0.0, 140.0), PI * 0.5))
	AirfieldFurniture._prop_cluster(container, "hut", AirfieldAssets.nissen(team), huts, team, 3)
	# ammunition: dispersed sandbag bays along the west side; fuel: drum dumps along the east side
	var ammo: Array = []
	for i in 5:
		ammo.append(_w(axf, yaw, Vector3(-258.0, 0.0, 66.0 + float(i) * 28.0), -PI * 0.5))
	AirfieldFurniture._prop_cluster(container, "ammo", CampAssets.ammo_bay(team), ammo, team, 3)
	var fuel: Array = []
	for i in 5:
		fuel.append(_w(axf, yaw, Vector3(258.0, 0.0, 70.0 + float(i) * 26.0), PI * 0.5))
	AirfieldFurniture._prop_cluster(container, "ammo", CampAssets.drum_dump(team), fuel, team, 3)
	# concertina round both dumps
	var wire: Array = []
	for i in 30:
		for sx in [-1.0, 1.0]:
			wire.append(_w(axf, yaw, Vector3(sx * 236.0, 0.0, 50.0 + float(i) * 5.0), PI * 0.5))
	container.add_child(Scatter.multi(CampAssets.concertina(), wire, 2200.0))
	# perimeter: wire fence with a gate, sentry towers at the corners
	container.add_child(Scatter.multi(CampAssets.fence_bay(false), CampAssets.fence_ring(axf, yaw, HX, HZ, 9.0), 2600.0))
	var gate: Array = [_w(axf, yaw, Vector3(0.0, 0.0, HZ), 0.0)]
	container.add_child(Scatter.multi(CampAssets.gate(team), gate, 3000.0))
	var towers: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			towers.append(_w(axf, yaw, Vector3(sx * (HX - 5.0), 0.0, sz * (HZ - 5.0)), PI * 0.25 * sx * sz))
	towers.append(_w(axf, yaw, Vector3(16.0, 0.0, HZ - 8.0), 0.0))
	container.add_child(Scatter.multi(CampAssets.guard_tower("army"), towers, 4500.0))
	# flagpole by the orderly room
	var fp: Vector3 = axf * Vector3(-90.0, 0.0, 150.0)
	var fy: float = GroundKit.ground_y(fp.x, fp.z)
	GroundKit.cyl(container, 0.1, 0.16, 12.0, Vector3(fp.x, fy + 6.0, fp.z), Color(0.85, 0.85, 0.82), Vector3.ZERO, 6, false)
	GroundKit.box(container, Vector3(3.0, 1.8, 0.1), Vector3(fp.x + 1.6, fy + 11.0, fp.z), Color(0.12, 0.18, 0.48) if allied else Color(0.65, 0.1, 0.1), Vector3(0, rad_to_deg(yaw), 0), false)
	# a pair of light AA guns covering the park
	for lp in [Vector3(-260.0, 0.0, -150.0), Vector3(260.0, 0.0, 30.0)]:
		var gp: Vector3 = axf * lp
		var g: AAGun = AAGun.create("bofors" if allied else "mg", team)
		g.position = Vector3(gp.x, GroundKit.ground_y(gp.x, gp.z), gp.z)
		container.add_child(g)
	# trees: the camps were pitched in parkland and along wooded lanes - keep the old hedgerow trees standing
	# between the lines, and a looser belt round the outside of the wire
	var avoid: Array = [
		[Vector3(-166, 0, -93), Vector2(52, 24)], [Vector3(-165, 0, -33), Vector2(44, 14)], [Vector3(120, 0, -95), Vector2(60, 18)],
		[Vector3(-150, 0, 40), Vector2(60, 10)], [Vector3(90, 0, 50), Vector2(68, 50)], [Vector3(225, 0, 32), Vector2(12, 52)],
		[Vector3(-5, 0, 140), Vector2(68, 10)], [Vector3(-248, 0, 122), Vector2(22, 66)], [Vector3(248, 0, 122), Vector2(22, 66)],
		[Vector3(0, 0, 0), Vector2(8, HZ + 40.0)], [Vector3(0, 0, -60), Vector2(HX, 6)], [Vector3(0, 0, 110), Vector2(HX, 6)],
		[Vector3(-260, 0, -150), Vector2(10, 10)], [Vector3(260, 0, 30), Vector2(10, 10)], [Vector3(-90, 0, 150), Vector2(6, 6)],
	]
	CampAssets.add_trees(container, CampAssets.tree_xforms(axf, rng, HX - 12.0, HZ - 12.0, 55, avoid))
	var belt: Array = [[], []]
	for i in 70:
		var a: float = rng.randf() * TAU
		var lp2 := Vector3(cos(a) * (HX + rng.randf_range(15.0, 60.0)), 0.0, sin(a) * (HZ + rng.randf_range(15.0, 60.0)))
		if absf(lp2.x) < 20.0 and lp2.z > 0.0:
			continue   # keep the lane to the gate open
		var p: Vector3 = axf * lp2
		if GroundKit.raw_y(p.x, p.z) < 1.0:
			continue
		var sc: float = rng.randf_range(0.85, 1.3)
		(belt[i % 2] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc)), Vector3(p.x, GroundKit.ground_y(p.x, p.z) - 0.3, p.z)))
	CampAssets.add_trees(container, belt)


## World transform of a camp item at a local point (ground height sampled there), turned by the camp yaw.
static func _w(axf: Transform3D, yaw: float, lp: Vector3, extra_yaw: float) -> Transform3D:
	var p: Vector3 = axf * lp
	p.y = GroundKit.ground_y(p.x, p.z)
	return Transform3D(Basis(Vector3.UP, yaw + extra_yaw), p)
