class_name HarbourWar
extends RefCounted
## Dated war damage to the big ports, from the C5 harbour survey (docs/map_research/C_D_life_horizon.md):
##
##  * Dunkirk: the ships sunk in the harbour and along the mole during the evacuation of May-June 1940
##    stayed there for the rest of the war (Wikipedia: Dunkirk evacuation; Operation Dynamo).
##  * Zeebrugge: the three concrete-filled blockships (Thetis, Intrepid, Iris) sunk in the mole harbour
##    on St George's Day 1918 still lay there through WW2 (Wikipedia: Zeebrugge Raid).
##  * Cherbourg: the German demolitions of 26-27 June 1944 - cranes toppled, quays and basins wrecked,
##    the port useless for weeks (Wikipedia: Battle of Cherbourg).
##  * Le Havre: flattened by the September 1944 RAF raids and the fighting for the port (Wikipedia:
##    Battle of Le Havre / Operation Astonia).
##  * IJmuiden: the German S-boat bunker on the south harbour, built from mid-1942 (Wikipedia:
##    Schnellbootbunker (IJmuiden)); five covered slips facing the water.
##
## Always registered (like the Mulberries); build() returns an empty node before each window opens and
## the wrecks stay for the rest of the war. Water line at y = 0.

const VIS_WRECK := 12000.0
const VIS_NEAR := 5500.0

# id -> layout. heading: degrees, the direction along which wreck rows / pen faces are laid.
const SITES := {
	"dunkirk_wrecks": {
		"kind": "wrecks", "lat": 51.0445, "lon": 2.3720, "heading": 64.0,
		"from": "1940-06-02", "to": "",
		"source": "Wikipedia: Dunkirk evacuation - ships sunk in the harbour and approach channels, June 1940",
	},
	"zeebrugge_blockships": {
		"kind": "blockships", "lat": 51.3480, "lon": 3.1965, "heading": 302.0,
		"from": "1939-09-01", "to": "",
		"source": "Wikipedia: Zeebrugge Raid - the 1918 blockships still in the mole harbour through WW2",
	},
	"cherbourg_demolitions": {
		"kind": "demolitions", "lat": 49.6480, "lon": -1.6210, "heading": 122.0,
		"from": "1944-06-27", "to": "",
		"source": "Wikipedia: Battle of Cherbourg - German demolitions of 26-27 June 1944",
	},
	"lehavre_demolitions": {
		"kind": "demolitions", "lat": 49.4900, "lon": 0.0980, "heading": 96.0,
		"from": "1944-09-12", "to": "",
		"source": "Wikipedia: Battle of Le Havre (Operation Astonia) - the wrecked port basins, September 1944",
	},
	"ijmuiden_pens": {
		"kind": "eboat_pens", "lat": 52.4590, "lon": 4.5980, "heading": 205.0,
		"from": "1942-07-01", "to": "",
		"source": "Wikipedia: Schnellbootbunker (IJmuiden) - the S-boat shelter built from 1942",
	},
}


static func world(ll: Array) -> Vector3:
	return WorldCoords.latlon_to_world(float(ll[0]), float(ll[1]))


static func centre(id: String) -> Vector3:
	return world([SITES[id]["lat"], SITES[id]["lon"]])


## True when anything of this site exists on the current war date.
static func active(id: String) -> bool:
	return EraClock.is_between(str(SITES[id]["from"]), str(SITES[id]["to"]))


static func build(id: String) -> Node3D:
	var st: Dictionary = SITES[id]
	var root := Node3D.new()
	root.name = "HarbourWar_" + id
	if not active(id):
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("harbourwar_" + id)
	var org: Vector3 = centre(id)
	var head: float = deg_to_rad(float(st["heading"]))
	var along := Vector3(sin(head), 0.0, cos(head))
	var across := Vector3(-along.z, 0.0, along.x)
	match str(st["kind"]):
		"wrecks":
			# a line of sunk and burnt hulls in the basin, a couple across the entrance
			var sunk: Array = []
			var burnt: Array = []
			for i in 7:
				var p: Vector3 = org + along * (-260.0 + float(i) * 85.0) + across * rng.randf_range(-55.0, 55.0)
				var yaw: float = head + rng.randf_range(-0.5, 0.5)
				if i == 2 or i == 5:
					yaw = head + PI * rng.randf_range(0.35, 0.65)   # the ones that block the entrance lie across it
				var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.z))
				(burnt if i % 3 == 1 else sunk).append(xf)
			root.add_child(Scatter.multi(wreck_mesh(false), sunk, VIS_WRECK))
			root.add_child(Scatter.multi(wreck_mesh(true), burnt, VIS_WRECK))
		"blockships":
			# three old cruisers run bow-on into the mole gap, sterns just showing
			var ships: Array = []
			for i in 3:
				var p2: Vector3 = org + across * (float(i) - 1.0) * 46.0
				ships.append(Transform3D(Basis(Vector3.UP, head + PI), Vector3(p2.x, 0.0, p2.z)))
			var bm: MultiMeshInstance3D = Scatter.multi(MulberryKit.blockship_mesh(), ships, VIS_WRECK)
			bm.scale = Vector3(0.62, 0.62, 0.62)
			root.add_child(bm)
		"demolitions":
			# toppled cranes along the quay, heaps of rubble, two burnt hulls in the basin
			var cranes: Array = []
			for i in 5:
				var c: Vector3 = org + along * (-300.0 + float(i) * 150.0) - across * 190.0
				cranes.append(Transform3D(Basis(Vector3.UP, head + PI * 0.5 + rng.randf_range(-0.15, 0.15)), Vector3(c.x, 0.0, c.z)))
			root.add_child(Scatter.multi(toppled_crane_mesh(), cranes, VIS_NEAR))
			var heaps: Array = []
			for i in 9:
				var r: Vector3 = org + along * (-360.0 + float(i) * 92.0) - across * rng.randf_range(130.0, 250.0)
				heaps.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(r.x, 0.0, r.z)))
			root.add_child(Scatter.multi(rubble_heap_mesh(), heaps, VIS_NEAR))
			var hulls: Array = []
			for i in 2:
				var h2: Vector3 = org + along * (-180.0 + float(i) * 340.0) + across * 150.0
				hulls.append(Transform3D(Basis(Vector3.UP, head + rng.randf_range(-0.4, 0.4)), Vector3(h2.x, 0.0, h2.z)))
			root.add_child(Scatter.multi(wreck_mesh(true), hulls, VIS_WRECK))
		"eboat_pens":
			var pens: Array = [Transform3D(Basis(Vector3.UP, head), Vector3(org.x, 0.0, org.z))]
			root.add_child(Scatter.multi(eboat_pen_mesh(), pens, VIS_NEAR))
	return root


# ------------------------------------------------------------------ meshes (water line at y = 0)
static func _keep(key: String, parts: Array) -> ArrayMesh:
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m


## A wrecked merchantman: hull sitting on the bottom with only the port side and bow showing, listing
## `burnt=true` adds a collapsed, soot-black superstructure (the burnt-out ships of June 1940).
## Long axis along X; ~95 m overall.
static func wreck_mesh(burnt: bool) -> ArrayMesh:
	var key: String = "hw_wreck_burnt" if burnt else "hw_wreck"
	if Scatter._meshes.has(key):
		return Scatter._meshes[key]
	var hull := Color(0.23, 0.22, 0.21) if burnt else Color(0.30, 0.27, 0.24)
	var weed := Color(0.22, 0.24, 0.20)
	var parts: Array = []
	# the deck edge and one side just clear the water, the rest is under
	parts.append(GroundKit.box_part(Vector3(95.0, 2.6, 13.5), Vector3(0, 1.1, 0), hull))
	parts.append(GroundKit.box_part(Vector3(95.0, 1.0, 13.9), Vector3(0, 0.3, 0), weed, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(13.0, 3.4, 12.0), Vector3(38.0, 1.4, 0), hull, Vector3(0, 0, 8), false))   # lifted bow
	if burnt:
		parts.append(GroundKit.box_part(Vector3(11.0, 4.2, 10.0), Vector3(-8.0, 2.6, 0), Color(0.14, 0.13, 0.12), Vector3(0, 0, 10), false))
		parts.append(GroundKit.box_part(Vector3(3.0, 2.2, 3.0), Vector3(-18.0, 1.2, 2.0), Color(0.16, 0.15, 0.14), Vector3(0, 0, -14), false))
	else:
		parts.append(GroundKit.box_part(Vector3(12.0, 5.5, 11.0), Vector3(-8.0, 4.4, 0), Color(0.42, 0.40, 0.35)))
		parts.append(GroundKit.cyl_part(1.5, 1.7, 8.0, Vector3(4.0, 7.5, 0), Color(0.20, 0.19, 0.18), Vector3.ZERO, 8, false))
	return _keep(key, parts)


## A harbour crane toppled onto the quay: lying lattice tower with the jib bent down into the basin.
static func toppled_crane_mesh() -> ArrayMesh:
	if Scatter._meshes.has("hw_crane"):
		return Scatter._meshes["hw_crane"]
	var steel := Color(0.30, 0.31, 0.30)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(16.0, 2.4, 2.4), Vector3(0, 1.2, 0), steel))
	parts.append(GroundKit.box_part(Vector3(14.0, 1.6, 1.4), Vector3(17.0, 0.8, 0), steel, Vector3(0, 0, -18), false))
	parts.append(GroundKit.box_part(Vector3(2.0, 2.0, 2.0), Vector3(-9.5, 1.0, 0), Color(0.24, 0.23, 0.21)))
	return _keep("hw_crane", parts)


## A demolition heap: broken concrete and twisted steel on the quay edge.
static func rubble_heap_mesh() -> ArrayMesh:
	if Scatter._meshes.has("hw_rubble"):
		return Scatter._meshes["hw_rubble"]
	var conc := Color(0.48, 0.46, 0.42)
	var dark := Color(0.30, 0.29, 0.26)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(16.0, 3.2, 13.0), Vector3(0, 1.0, 0), conc, Vector3(0, 14, 0), false))
	parts.append(GroundKit.box_part(Vector3(9.0, 2.4, 8.0), Vector3(5.0, 2.6, -2.0), dark, Vector3(0, -20, 6), false))
	parts.append(GroundKit.box_part(Vector3(5.0, 1.6, 4.0), Vector3(-6.0, 2.4, 3.0), conc.darkened(0.1), Vector3(0, 30, -8), false))
	return _keep("hw_rubble", parts)


## The IJmuiden S-boat shelter: a tall concrete bunker, five dark covered slips facing the water,
## slip aprons in front. Long face along X (local), the slips on the +Z side.
static func eboat_pen_mesh() -> ArrayMesh:
	if Scatter._meshes.has("hw_eboat_pen"):
		return Scatter._meshes["hw_eboat_pen"]
	var conc := Color(0.55, 0.54, 0.50)
	var tide := Color(0.28, 0.30, 0.26)
	var dark := Color(0.10, 0.10, 0.10)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(84.0, 11.0, 26.0), Vector3(0, 5.5, 0), conc))
	for i in 5:
		var sx: float = -33.6 + float(i) * 16.8
		parts.append(GroundKit.box_part(Vector3(12.0, 8.0, 1.4), Vector3(sx, 4.0, 13.2), dark))
		parts.append(GroundKit.box_part(Vector3(12.0, 0.6, 14.0), Vector3(sx, 0.3, 20.5), tide, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(86.0, 1.0, 27.0), Vector3(0, 0.5, 0), tide, Vector3.ZERO, false))
	return _keep("hw_eboat_pen", parts)
