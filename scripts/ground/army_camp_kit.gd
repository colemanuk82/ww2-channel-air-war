class_name ArmyCampKit
extends RefCounted
## Large army camps beside some airfields: a tank park in rows on worn ground, half-track and lorry lines, a
## field-gun battery, bell-tent lines and marquees, Nissen huts, fuel and ammunition dumps, with a couple of light
## AA guns. The Allied camps are the 1944 build-up round the south-coast fighter stations and landing grounds
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

const CAMP_RADIUS := 330.0


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
			var q: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * 260.0
			ok = ok and GroundKit.raw_y(q.x, q.z) > 1.5
		if ok:
			return c
	return Vector3.INF


static func build(container: Node3D, center: Vector3, heading_deg: float, team: String, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var yaw: float = -deg_to_rad(heading_deg)
	var axf := Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0.0, center.z))
	var allied: bool = team == "Allies"
	if OS.is_debug_build():
		var ll: Vector2 = WorldCoords.world_to_latlon(center)
		print("[camp] %s camp at %.4f, %.4f" % [team, ll.x, ll.y])

	# worn, rutted ground under each vehicle row (a strip per row, placed from the same coordinates as the
	# vehicles so it always lies under them, and short enough to follow the terrain)
	for row in [[-210.0, -122.0, -110.0], [-210.0, -122.0, -93.0], [-210.0, -122.0, -76.0], [-200.0, -130.0, -40.0],
			[-200.0, -130.0, -26.0], [70.0, 169.0, -110.0], [70.0, 169.0, -95.0], [70.0, 169.0, -80.0]]:
		var x0: float = row[0]
		var x1: float = row[1]
		var z: float = row[2]
		var mid: Vector3 = axf * Vector3((x0 + x1) * 0.5, 0.0, z)
		GroundKit.box(container, Vector3(x1 - x0 + 12.0, 0.2, 12.0), Vector3(mid.x, GroundKit.ground_y(mid.x, mid.z) + 0.06, mid.z), Color(0.29, 0.27, 0.19), Vector3(0.0, rad_to_deg(yaw), 0.0), false)

	# tank park: three rows facing out, as the photos of the 1944 marshalling areas show
	var tanks: Array = []
	for r in 3:
		for i in 9:
			tanks.append(_w(axf, yaw, Vector3(-210.0 + float(i) * 11.0 + rng.randf_range(-0.8, 0.8), 0.0, -110.0 + float(r) * 17.0), rng.randf_range(-0.04, 0.04)))
	AirfieldFurniture._prop_cluster(container, "tank", AirfieldAssets.tank(team), tanks, team, 4)
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
	# field-gun battery, guns in a line with their limbers behind
	var guns: Array = []
	for i in 6:
		guns.append(_w(axf, yaw, Vector3(-200.0 + float(i) * 20.0, 0.0, 40.0), 0.0))
	AirfieldFurniture._prop_cluster(container, "gun", AirfieldAssets.field_gun(team), guns, team, 3)
	# bell-tent lines (one MultiMesh) and marquees
	var tents: Array = []
	for r in 8:
		for i in 16:
			tents.append(_w(axf, yaw, Vector3(30.0 + float(i) * 8.0, 0.0, 10.0 + float(r) * 11.0), rng.randf_range(-0.06, 0.06)))
	container.add_child(Scatter.multi(AirfieldAssets.tent(team), tents, 3200.0))
	var marq: Array = []
	for i in 4:
		marq.append(_w(axf, yaw, Vector3(225.0, 0.0, -10.0 + float(i) * 28.0), 0.0))
	AirfieldFurniture._prop_cluster(container, "hut", AirfieldAssets.marquee(team), marq, team, 2)
	# Nissen huts (cookhouse, stores, orderly room)
	var huts: Array = []
	for i in 6:
		huts.append(_w(axf, yaw, Vector3(-60.0 + float(i) * 22.0, 0.0, 140.0), PI * 0.5))
	AirfieldFurniture._prop_cluster(container, "hut", AirfieldAssets.nissen(team), huts, team, 3)
	# fuel and ammunition dumps out on the edge
	var fuel: Array = []
	for i in 4:
		fuel.append(_w(axf, yaw, Vector3(250.0, 0.0, 110.0 + float(i) * 14.0), 0.0))
	AirfieldFurniture._prop_cluster(container, "ammo", AirfieldAssets.fuel_tank(), fuel, team, 4)
	var ammo: Array = []
	for i in 4:
		ammo.append(_w(axf, yaw, Vector3(-250.0, 0.0, 100.0 + float(i) * 22.0), PI * 0.5))
	AirfieldFurniture._prop_cluster(container, "ammo", AirfieldAssets.bomb_bank(), ammo, team, 4)
	# a pair of light AA guns covering the park
	for lp in [Vector3(-260.0, 0.0, -150.0), Vector3(260.0, 0.0, 30.0)]:
		var gp: Vector3 = axf * lp
		var g: AAGun = AAGun.create("bofors" if allied else "mg", team)
		g.position = Vector3(gp.x, GroundKit.ground_y(gp.x, gp.z), gp.z)
		container.add_child(g)


## World transform of a camp item at a local point (ground height sampled there), turned by the camp yaw.
static func _w(axf: Transform3D, yaw: float, lp: Vector3, extra_yaw: float) -> Transform3D:
	var p: Vector3 = axf * lp
	p.y = GroundKit.ground_y(p.x, p.z)
	return Transform3D(Basis(Vector3.UP, yaw + extra_yaw), p)
