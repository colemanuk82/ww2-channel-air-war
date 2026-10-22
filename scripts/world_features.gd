class_name WorldFeatures
extends RefCounted
## Real-location scenery builders used by WorldPopulator: harbours (quays, breakwaters, cranes, warehouses,
## moored ships and fishing boats) and army barracks / camps (brick barracks around a parade ground, Nissen-hut
## lines, tent lines, vehicle parks, fences, guard towers). Positions are the real lat/lon of the places.

const PORTS := [
	# id, name, lat, lon, side, size (1 fishing harbour .. 3 major port)
	["dover", "Dover", 51.1235, 1.3150, "Allies", 3],
	["folkestone", "Folkestone", 51.0775, 1.1930, "Allies", 2],
	["ramsgate", "Ramsgate", 51.3300, 1.4300, "Allies", 2],
	["newhaven", "Newhaven", 50.7920, 0.0560, "Allies", 2],
	["portsmouth", "Portsmouth", 50.8000, -1.1050, "Allies", 3],
	["southampton", "Southampton", 50.8980, -1.4150, "Allies", 3],
	["poole", "Poole", 50.7110, -1.9890, "Allies", 2],
	["sheerness", "Sheerness", 51.4440, 0.7440, "Allies", 2],
	["shoreham", "Shoreham", 50.8300, -0.2450, "Allies", 1],
	["hastings", "Hastings", 50.8500, 0.5930, "Allies", 1],
	["rye_harbour", "Rye Harbour", 50.9330, 0.7700, "Allies", 1],
	["calais", "Calais", 50.9650, 1.8500, "Axis", 3],
	["boulogne", "Boulogne", 50.7270, 1.5900, "Axis", 3],
	["dunkirk", "Dunkirk", 51.0500, 2.3700, "Axis", 3],
	["dieppe", "Dieppe", 49.9300, 1.0850, "Axis", 2],
	["le_havre", "Le Havre", 49.4850, 0.1050, "Axis", 3],
	["cherbourg", "Cherbourg", 49.6500, -1.6100, "Axis", 3],
	["ostend", "Ostend", 51.2300, 2.9200, "Axis", 3],
	["zeebrugge", "Zeebrugge", 51.3350, 3.2000, "Axis", 2],
	["le_treport", "Le Treport", 50.0650, 1.3750, "Axis", 1],
	["fecamp", "Fecamp", 49.7620, 0.3640, "Axis", 1],
	["etaples", "Etaples", 50.5150, 1.6370, "Axis", 1],
	["saint_valery", "Saint-Valery-en-Caux", 49.8680, 0.7100, "Axis", 1],
	["honfleur", "Honfleur", 49.4200, 0.2300, "Axis", 1],
	["courseulles", "Courseulles", 49.3350, -0.4560, "Axis", 1],
	["grandcamp", "Grandcamp-Maisy", 49.3900, -1.0400, "Axis", 1],
	# South-coast / Solent / Thames-estuary harbours missing from the original list (queued item b).
	["littlehampton", "Littlehampton", 50.8080, -0.5420, "Allies", 1],
	["portland", "Portland Harbour", 50.5700, -2.4400, "Allies", 2],
	["lymington", "Lymington", 50.7550, -1.5300, "Allies", 1],
	["cowes", "Cowes", 50.7620, -1.2960, "Allies", 1],
	["whitstable", "Whitstable", 51.3620, 1.0250, "Allies", 1],
	["tilbury", "Tilbury", 51.4580, 0.3550, "Allies", 3],
	["harwich", "Harwich", 51.9450, 1.2860, "Allies", 2],
]

const CAMPS := [
	# id, name, lat, lon, side, kind ("barracks" brick blocks / "camp" huts+tents), size 1-3
	["aldershot", "Aldershot Garrison", 51.2480, -0.7550, "Allies", "barracks", 3],
	["shorncliffe", "Shorncliffe Camp", 51.0830, 1.1480, "Allies", "camp", 3],
	["dover_castle", "Dover Castle garrison", 51.1280, 1.3220, "Allies", "barracks", 1],
	["chatham", "Chatham Barracks", 51.3890, 0.5260, "Allies", "barracks", 2],
	["canterbury_bks", "Canterbury Barracks", 51.2810, 1.0870, "Allies", "barracks", 1],
	["lydd", "Lydd Camp", 50.9500, 0.9100, "Allies", "camp", 2],
	["hythe", "Hythe Ranges camp", 51.0640, 1.0780, "Allies", "camp", 1],
	["pirbright", "Pirbright Camp", 51.2970, -0.6590, "Allies", "camp", 3],
	["bordon", "Bordon / Longmoor Camps", 51.1170, -0.8650, "Allies", "camp", 3],
	["chichester_bks", "Chichester Barracks", 50.8420, -0.7760, "Allies", "barracks", 1],
	["portsmouth_bks", "Fort Southwick", 50.8500, -1.0950, "Allies", "barracks", 2],
	["maidstone_bks", "Invicta Park Barracks", 51.2820, 0.5390, "Allies", "barracks", 2],
	["gravesend_bks", "Milton Barracks", 51.4350, 0.3650, "Allies", "barracks", 1],
	["deal_bks", "Royal Marines Barracks Deal", 51.2190, 1.4010, "Allies", "barracks", 2],
	["bexhill", "Bexhill Camp", 50.8440, 0.4700, "Allies", "camp", 2],
	["sandling", "Sandling Camp", 51.0980, 1.0600, "Allies", "camp", 2],
	["coquelles", "Coquelles Camp", 50.9300, 1.8100, "Axis", "camp", 3],
	["saint_omer_bks", "Saint-Omer Garrison", 50.7450, 2.2600, "Axis", "barracks", 3],
	["etaples_camp", "Etaples Camp", 50.5200, 1.6400, "Axis", "camp", 3],
	["boulogne_cit", "Boulogne Citadel", 50.7330, 1.6130, "Axis", "barracks", 1],
	["lille_cit", "Lille Citadel", 50.6420, 3.0450, "Axis", "barracks", 3],
	["amiens_cit", "Amiens Citadel", 49.8900, 2.3150, "Axis", "barracks", 2],
	["rouen_bks", "Rouen Caserne", 49.4400, 1.1000, "Axis", "barracks", 2],
	["caen_bks", "Caen Caserne", 49.1900, -0.3600, "Axis", "barracks", 2],
	["cherbourg_arsenal", "Cherbourg Arsenal barracks", 49.6450, -1.6200, "Axis", "barracks", 2],
	["le_havre_bks", "Le Havre Caserne", 49.5000, 0.1500, "Axis", "barracks", 2],
	["bruges_bks", "Bruges Barracks", 51.2050, 3.2200, "Axis", "barracks", 2],
	["ostend_bks", "Ostend Barracks", 51.2200, 2.9300, "Axis", "barracks", 1],
	["dunkirk_bks", "Dunkirk Caserne", 51.0380, 2.3800, "Axis", "barracks", 1],
	["arras_cit", "Arras Citadel", 50.2900, 2.7700, "Axis", "barracks", 2],
	["cambrai_bks", "Cambrai Barracks", 50.1750, 3.2300, "Axis", "barracks", 2],
	["abbeville_camp", "Abbeville Camp", 50.1050, 1.8400, "Axis", "camp", 2],
	["dieppe_bks", "Dieppe Garrison", 49.9250, 1.0700, "Axis", "barracks", 1],
	["valognes_camp", "Valognes Camp", 49.5100, -1.4700, "Axis", "camp", 2],
	["saint_lo_bks", "Saint-Lo Caserne", 49.1150, -1.0900, "Axis", "barracks", 1],
	["bayeux_camp", "Bayeux Camp", 49.2780, -0.7000, "Axis", "camp", 2],
	["sissonne", "Sissonne Camp", 49.5700, 3.9100, "Axis", "camp", 3],
	["le_touquet_camp", "Le Touquet Camp", 50.5200, 1.5900, "Axis", "camp", 1],
	["calais_bks", "Calais Garrison", 50.9500, 1.8700, "Axis", "barracks", 2],
]

static var _mesh_cache: Dictionary = {}


static func _h(root: Node3D, local: Vector3) -> float:
	var w: Vector3 = root.transform * local
	return GroundKit.ground_y(w.x, w.z)


# ============================================================================ ports
## Harbour built around a shoreline point. `sea` is the unit direction towards open water. Returns a container
## at the world origin (ships are world-space children, the harbour structure is a rotated child).
static func build_port(pos: Vector3, sea: Vector3, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(WorldCoords.dir_to_heading(sea))      # local -Z = towards the sea
	container.add_child(root)
	var k: float = 0.8 + 0.45 * float(size)
	var conc: Color = GroundKit.COL_CONCRETE
	var stone := Color(0.4, 0.4, 0.38)
	# quay slab straddling the waterline
	GroundKit.box(root, Vector3(330.0 * k, 2.4, 52.0), Vector3(0, 1.0, 8.0), conc.darkened(0.08))
	# two curved-ish breakwater arms with lights
	for sx in [-1.0, 1.0]:
		var arm_len: float = 300.0 * k
		GroundKit.box(root, Vector3(15.0, 4.8, arm_len), Vector3(sx * 190.0 * k, 1.6, -arm_len * 0.5 - 15.0), stone)
		GroundKit.box(root, Vector3(11.0, 1.2, arm_len * 0.93), Vector3(sx * 190.0 * k, 4.5, -arm_len * 0.5 - 15.0), conc)    # wave wall top
		var tip := Vector3(sx * 190.0 * k, 5.0, -arm_len - 20.0)
		GroundKit.cyl(root, 1.9, 2.6, 15.0, tip + Vector3(0, 7.5, 0), Color(0.92, 0.92, 0.9) if sx < 0.0 else Color(0.75, 0.15, 0.12), Vector3.ZERO, 10)
		GroundKit.box(root, Vector3(3.6, 2.4, 3.6), tip + Vector3(0, 16.0, 0), Color(0.15, 0.15, 0.17))
	# finger piers
	var n_piers: int = 1 + size
	for i in n_piers:
		var fx: float = (float(i) - float(n_piers - 1) * 0.5) * (110.0 * k / float(maxi(n_piers - 1, 1))) * 1.6
		GroundKit.box(root, Vector3(13.0, 2.2, 120.0 * k), Vector3(fx, 0.9, -60.0 * k - 10.0), conc)
		for b in 3:
			GroundKit.box(root, Vector3(0.9, 1.8, 0.9), Vector3(fx + 6.5, 2.6, -20.0 - float(b) * 30.0 * k), GroundKit.COL_DARK, Vector3.ZERO, false)
	# dockside cranes
	for i in 2 + size:
		var cx: float = (float(i) - float(1 + size) * 0.5) * 55.0 * k
		var cz: float = -10.0
		GroundKit.box(root, Vector3(4.0, 22.0, 4.0), Vector3(cx, 13.0, cz), Color(0.7, 0.18, 0.12))
		GroundKit.box(root, Vector3(3.0, 3.0, 36.0), Vector3(cx, 24.0, cz - 10.0), Color(0.7, 0.18, 0.12))
		GroundKit.box(root, Vector3(2.0, 2.0, 12.0), Vector3(cx, 24.0, cz + 20.0), GroundKit.COL_STEEL)
		GroundKit.box(root, Vector3(0.5, 12.0, 0.5), Vector3(cx, 17.0, cz - 24.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	# warehouses and sheds behind the quay (brick, pitched roofs)
	for i in 3 + size * 3:
		var wx: float = rng.randf_range(-150.0, 150.0) * k
		var wz: float = rng.randf_range(48.0, 90.0 + 70.0 * float(size))
		var w: float = rng.randf_range(24.0, 50.0)
		var l: float = rng.randf_range(18.0, 34.0)
		var hgt: float = rng.randf_range(8.0, 13.0)
		var gy: float = _h(root, Vector3(wx, 0, wz))
		var wall: Color = Color(0.5, 0.3, 0.24) if rng.randf() < 0.5 else Color(0.55, 0.52, 0.45)
		GroundKit.box(root, Vector3(w, hgt, l), Vector3(wx, gy + hgt * 0.5, wz), wall)
		GroundKit.box(root, Vector3(w * 1.04, 1.5, l * 1.04), Vector3(wx, gy + hgt + 0.7, wz), Color(0.28, 0.27, 0.29))
		GroundKit.box(root, Vector3(w * 0.9, 2.2, l * 0.5), Vector3(wx, gy + hgt + 2.2, wz), Color(0.3, 0.29, 0.31), Vector3(0, 0, 0))
	# fuel tanks at the larger ports
	if size >= 2:
		for i in 3:
			var tx: float = -120.0 * k + float(i) * 26.0
			var tgy: float = _h(root, Vector3(tx, 0, 190.0))
			GroundKit.cyl(root, 11.0, 11.0, 12.0, Vector3(tx, tgy + 6.0, 190.0), Color(0.62, 0.62, 0.6), Vector3.ZERO, 14)
	# harbour lamp posts / bollards line along the quay
	for i in 10:
		var lx: float = (float(i) - 4.5) * 28.0 * k
		GroundKit.cyl(root, 0.18, 0.2, 6.0, Vector3(lx, 4.4, -12.0), GroundKit.COL_DARK, Vector3.ZERO, 5, false)
	# moored ships: world-space stationary ships along the piers and in the basin
	var ship_n: int = 2 + size * 2
	var types: Array = ["fishing_boat", "fishing_boat", "freighter", "destroyer"] if size >= 2 else ["fishing_boat", "fishing_boat", "fishing_boat"]
	if size >= 3:
		types.append("freighter")
	for i in ship_n:
		var t: String = types[rng.randi() % types.size()]
		var lx2: float = rng.randf_range(-120.0, 120.0) * k
		var lz2: float = -rng.randf_range(24.0, 85.0) * k
		var wp: Vector3 = root.transform * Vector3(lx2, 0, lz2)
		var along: Vector3 = (root.transform.basis * Vector3(0, 0, -1)).normalized()
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([wp, wp + along * 6.0]))
		var sh: GroundShip = GroundShip.create(t, team, rp, 0.0, 0.0)
		sh.speed = 0.0
		sh.wrap = false
		container.add_child(sh)
	return container


# ==================================================================== piers & docks
## Long pleasure pier (the Brighton/Eastbourne/Hastings/Deal silhouette): a timber trestle deck running out to
## sea on piles, a boarding kiosk at the shore end, lamp posts, and a castellated pavilion at the head with a
## pleasure steamer alongside. `sea` is the unit direction towards open water (local -Z = towards the sea).
static func build_pleasure_pier(pos: Vector3, sea: Vector3, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(WorldCoords.dir_to_heading(sea))      # local -Z = towards the sea
	container.add_child(root)
	var k: float = 0.85 + 0.5 * float(size)
	var deck_y: float = 3.6
	var length: float = 150.0 * k
	var width: float = 9.0
	var deck: Color = Color(0.55, 0.44, 0.32)        # timber decking
	var iron: Color = Color(0.30, 0.31, 0.33)        # cast-iron piles / railings
	var cream: Color = Color(0.86, 0.83, 0.72)       # painted pavilion
	# segmented deck out over the water
	var seg: int = int(length / 18.0)
	for i in seg:
		var seg_l: float = length / float(seg)
		var z: float = -6.0 - (float(i) + 0.5) * seg_l
		GroundKit.box(root, Vector3(width, 0.6, seg_l - 0.4), Vector3(0, deck_y, z), deck)
		GroundKit.box(root, Vector3(width + 0.6, 0.35, 0.5), Vector3(0, deck_y + 0.25, z + seg_l * 0.5), iron, Vector3.ZERO, false)
	# trestle piles: pairs down into the water with cross-bracing
	var n_pile: int = int(length / 12.0)
	for i in n_pile:
		var z2: float = -6.0 - float(i) * (length / float(maxi(n_pile - 1, 1)))
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(root, 0.55, 0.65, deck_y + 4.0, Vector3(sx * (width * 0.5 - 0.8), deck_y * 0.5 - 2.0, z2), iron, Vector3.ZERO, 6, false)
		GroundKit.box(root, Vector3(width, 0.5, 0.5), Vector3(0, deck_y - 1.6, z2), iron, Vector3.ZERO, false)
	# railings along both edges
	for sx2 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(0.18, 1.1, length), Vector3(sx2 * (width * 0.5 - 0.2), deck_y + 0.9, -6.0 - length * 0.5), iron, Vector3.ZERO, false)
	# shore-end entrance building + boarding kiosk
	GroundKit.box(root, Vector3(width + 4.0, 5.5, 7.0), Vector3(0, 2.6, 0.0), cream)
	GroundKit.box(root, Vector3(width + 5.0, 1.4, 8.0), Vector3(0, 5.6, 0.0), iron, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(7.0, 4.0, 5.0), Vector3(width * 0.5 + 4.5, 2.0, -8.0), Color(0.5, 0.32, 0.24))
	var kiosk_roof := MeshInstance3D.new()
	kiosk_roof.mesh = GroundKit.prism_mesh(7.4, 5.4, 2.2)
	kiosk_roof.material_override = GroundKit.mat(Color(0.35, 0.24, 0.18), true)
	kiosk_roof.position = Vector3(width * 0.5 + 4.5, 4.0, -8.0)
	root.add_child(kiosk_roof)
	# the pavilion at the head of the pier
	var pz: float = -length - 6.0
	GroundKit.box(root, Vector3(22.0, 7.5, 20.0), Vector3(0, deck_y + 3.75, pz), cream)
	GroundKit.box(root, Vector3(23.0, 1.2, 21.0), Vector3(0, deck_y + 8.0, pz), iron)
	var proof := MeshInstance3D.new()
	proof.mesh = GroundKit.prism_mesh(24.0, 22.0, 5.0)
	proof.material_override = GroundKit.mat(Color(0.4, 0.42, 0.5), true)
	proof.position = Vector3(0, deck_y + 8.6, pz)
	root.add_child(proof)
	for i in 8:                                        # veranda posts round the pavilion
		var a: float = TAU * float(i) / 8.0
		GroundKit.cyl(root, 0.22, 0.22, 6.0, Vector3(cos(a) * 10.5, deck_y + 3.0, pz + sin(a) * 9.5), cream, Vector3.ZERO, 5, false)
	# lamp posts along the deck
	for i in 6:
		var lz: float = -10.0 - float(i) * (length / 6.0)
		GroundKit.cyl(root, 0.14, 0.16, 5.0, Vector3(width * 0.5 - 0.6, deck_y + 3.0, lz), iron, Vector3.ZERO, 5, false)
		GroundKit.box(root, Vector3(0.8, 1.0, 0.8), Vector3(width * 0.5 - 0.6, deck_y + 5.8, lz), Color(0.95, 0.9, 0.6), Vector3.ZERO, false)
	# a pleasure steamer alongside the head
	var along: Vector3 = (root.transform.basis * Vector3(0, 0, -1)).normalized()
	var wp: Vector3 = root.transform * Vector3(16.0, 0.0, pz + 4.0)
	var rp: RoutePath = RoutePath.from_points(PackedVector3Array([wp, wp + along * 8.0]))
	var sh: GroundShip = GroundShip.create("freighter", team, rp, 0.0, 0.0)
	sh.speed = 0.0
	sh.wrap = false
	container.add_child(sh)
	return container


## Enclosed commercial dock basin: concrete quay walls around a rectangular basin, an entrance lock with pivoted
## gates and breakwater piers, dockside cranes, transit sheds and moored ships inside the basin.
static func build_dock_basin(pos: Vector3, sea: Vector3, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(WorldCoords.dir_to_heading(sea))      # local -Z = towards the sea (the entrance)
	container.add_child(root)
	var k: float = 0.9 + 0.5 * float(size)
	var conc: Color = GroundKit.COL_CONCRETE
	var stone := Color(0.42, 0.42, 0.4)
	var bw: float = 200.0 * k                           # basin width (X)
	var bl: float = 300.0 * k                           # basin length (Z)
	var wall_h: float = 5.0
	# land-side quay slabs wrapping the basin (head + both flanks)
	GroundKit.box(root, Vector3(bw + 90.0, 3.0, 70.0), Vector3(0, 1.2, bl * 0.5 + 35.0), conc.darkened(0.08))
	for sx in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(60.0, 3.0, bl + 40.0), Vector3(sx * (bw * 0.5 + 30.0), 1.2, 0.0), conc.darkened(0.08))
	# basin wall faces: far wall + two side walls standing just above the waterline
	GroundKit.box(root, Vector3(bw, wall_h, 4.0), Vector3(0, wall_h * 0.5 - 1.0, bl * 0.5 - 2.0), stone)
	for sx2 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(4.0, wall_h, bl), Vector3(sx2 * (bw * 0.5 - 2.0), wall_h * 0.5 - 1.0, 0.0), stone)
	# entrance: two lock-gate piers flanking the channel plus the pivoted gate leaves
	for sx3 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(16.0, wall_h + 2.0, 22.0), Vector3(sx3 * (bw * 0.5 - 8.0), (wall_h + 2.0) * 0.5 - 1.0, -bl * 0.5 + 2.0), conc)
		GroundKit.box(root, Vector3(30.0, 1.2, 4.0), Vector3(sx3 * (bw * 0.5 - 8.0 + 8.0), wall_h + 2.4, -bl * 0.5 + 2.0), stone, Vector3(0, 0, sx3 * 26.0), false)
	# outer breakwater stubs either side of the entrance
	for sx4 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(14.0, wall_h, 130.0), Vector3(sx4 * (bw * 0.5 + 12.0), wall_h * 0.5 - 0.6, -bl * 0.5 - 60.0), stone)
	# dockside cranes on both flanking quays
	var n_crane: int = 3 + size
	for i in n_crane:
		var side_c: float = -1.0 if i % 2 == 0 else 1.0
		var cz: float = -bl * 0.4 + float(i) * (bl * 0.7 / float(n_crane))
		var cx: float = side_c * (bw * 0.5 + 14.0)
		GroundKit.box(root, Vector3(4.0, 22.0, 4.0), Vector3(cx, 13.0, cz), Color(0.7, 0.18, 0.12))
		GroundKit.box(root, Vector3(26.0, 3.0, 3.0), Vector3(cx - side_c * 13.0, 24.0, cz), Color(0.7, 0.18, 0.12))
		GroundKit.box(root, Vector3(0.5, 12.0, 0.5), Vector3(cx - side_c * 24.0, 18.0, cz), GroundKit.COL_DARK, Vector3.ZERO, false)
	# transit sheds (long low brick sheds with pitched roofs) behind the quays
	var sheds: int = 2 + size
	for i in sheds:
		var sx5: float = -1.0 if i % 2 == 0 else 1.0
		var sh_x: float = sx5 * (bw * 0.5 + 52.0)
		var sh_z: float = -bl * 0.3 + float(i) * 40.0
		var gy: float = _h(root, Vector3(sh_x, 0, sh_z))
		GroundKit.box(root, Vector3(26.0, 9.0, 90.0), Vector3(sh_x, gy + 4.5, sh_z), Color(0.5, 0.32, 0.25))
		var sroof := MeshInstance3D.new()
		sroof.mesh = GroundKit.prism_mesh(27.0, 91.0, 4.0)
		sroof.material_override = GroundKit.mat(Color(0.3, 0.29, 0.31), true)
		sroof.position = Vector3(sh_x, gy + 9.0, sh_z)
		root.add_child(sroof)
	# bollards along the head quay
	for i in 8:
		GroundKit.cyl(root, 0.4, 0.5, 1.6, Vector3((float(i) - 3.5) * (bw / 8.0), 2.6, bl * 0.5 + 20.0), GroundKit.COL_DARK, Vector3.ZERO, 6, false)
	# moored ships inside the basin
	var along: Vector3 = (root.transform.basis * Vector3(0, 0, -1)).normalized()
	var types: Array = ["freighter", "freighter", "landing_craft", "fishing_boat"] if size >= 2 else ["fishing_boat", "landing_craft"]
	var ship_n: int = 2 + size
	for i in ship_n:
		var t: String = types[rng.randi() % types.size()]
		var lx: float = rng.randf_range(-0.35, 0.35) * bw
		var lz: float = rng.randf_range(-0.35, 0.35) * bl
		var wp: Vector3 = root.transform * Vector3(lx, 0, lz)
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([wp, wp + along * 8.0]))
		var sh: GroundShip = GroundShip.create(t, team, rp, 0.0, 0.0)
		sh.speed = 0.0
		sh.wrap = false
		container.add_child(sh)
	return container


## Dry dock and shipyard: stepped graving docks with caisson gates, building slipways with hulls on the ways,
## a portal gantry crane over the fitting-out berth, a moored hull and a couple of hulked hulls on the foreshore.
static func build_drydock_shipyard(pos: Vector3, sea: Vector3, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(WorldCoords.dir_to_heading(sea))      # local -Z = towards the sea
	container.add_child(root)
	var k: float = 0.9 + 0.5 * float(size)
	var conc: Color = GroundKit.COL_CONCRETE
	var stone := Color(0.44, 0.44, 0.42)
	var steel := Color(0.55, 0.2, 0.16)                 # shipyard crane red
	# the yard apron / quay floor
	GroundKit.box(root, Vector3(300.0 * k, 2.4, 240.0 * k), Vector3(0, 0.9, 40.0), conc.darkened(0.12))
	# stepped graving dry docks, each open to the sea at -Z
	var n_dock: int = 1 + size / 2
	for d in n_dock:
		var dx: float = (float(d) - float(n_dock - 1) * 0.5) * 120.0
		var dl: float = 150.0
		var dw: float = 60.0
		var dz: float = -dl * 0.5 - 10.0
		for step in 3:                                  # three stepped wall courses dropping into the pit
			var inset: float = float(step) * 3.0
			GroundKit.box(root, Vector3(dw - inset * 2.0, 1.6, dl - inset * 2.0), Vector3(dx, 4.5 - float(step) * 1.6, dz), conc.darkened(0.06 + 0.03 * float(step)))
		GroundKit.box(root, Vector3(dw - 18.0, 0.8, dl - 18.0), Vector3(dx, -2.2, dz), Color(0.28, 0.28, 0.27), Vector3.ZERO, false)   # dock floor
		GroundKit.box(root, Vector3(dw - 4.0, 6.0, 5.0), Vector3(dx, 0.5, dz - dl * 0.5 + 2.0), Color(0.32, 0.3, 0.28))               # caisson gate
		if d == 0:                                      # a ship on the blocks in the first dock
			GroundKit.box(root, Vector3(14.0, 6.0, 80.0), Vector3(dx, 1.0, dz), Color(0.35, 0.37, 0.4))
			GroundKit.box(root, Vector3(11.0, 4.0, 24.0), Vector3(dx, 4.0, dz + 18.0), Color(0.5, 0.5, 0.48))
	# building slipways down to the water with hulls on the ways
	for s in 2:
		var slx: float = -90.0 + float(s) * 180.0
		GroundKit.box(root, Vector3(34.0, 1.2, 130.0), Vector3(slx, 1.0, -30.0), stone, Vector3(9.0, 0, 0))
		for b in 6:
			GroundKit.box(root, Vector3(4.0, 1.4, 4.0), Vector3(slx, 2.0, -70.0 + float(b) * 12.0), GroundKit.COL_DARK, Vector3.ZERO, false)
		GroundKit.box(root, Vector3(13.0, 5.0, 70.0), Vector3(slx, 3.4, -40.0), Color(0.4, 0.4, 0.42))
		GroundKit.box(root, Vector3(9.0, 3.0, 20.0), Vector3(slx, 6.0, -20.0), Color(0.45, 0.45, 0.47))
	# portal gantry crane over the fitting-out berth
	var gx: float = 70.0
	var leg_h: float = 34.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			GroundKit.box(root, Vector3(3.0, leg_h, 3.0), Vector3(gx + sx * 26.0, leg_h * 0.5 + 2.0, 0.0 + sz * 60.0), steel, Vector3.ZERO, false)
	for sz2 in [-1.0, 1.0]:
		GroundKit.box(root, Vector3(60.0, 3.0, 3.0), Vector3(gx, leg_h + 2.0, sz2 * 60.0), steel, Vector3.ZERO, false)
	GroundKit.box(root, Vector3(5.0, 4.0, 5.0), Vector3(gx, leg_h - 2.0, 0.0), GroundKit.COL_STEEL)
	GroundKit.box(root, Vector3(1.0, 12.0, 1.0), Vector3(gx, leg_h - 10.0, 0.0), GroundKit.COL_DARK, Vector3.ZERO, false)
	# fitting-out quay with a moored hull + hulked hulls on the foreshore
	var along: Vector3 = (root.transform.basis * Vector3(0, 0, -1)).normalized()
	var types: Array = ["freighter", "destroyer", "landing_craft"] if size >= 2 else ["fishing_boat", "freighter"]
	var ship_n: int = 2 + size
	for i in ship_n:
		var t: String = types[rng.randi() % types.size()]
		var wp: Vector3 = root.transform * Vector3(rng.randf_range(-140.0, 140.0), 0, -rng.randf_range(120.0, 220.0) * k)
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([wp, wp + along * 8.0]))
		var sh: GroundShip = GroundShip.create(t, team, rp, 0.0, 0.0)
		sh.speed = 0.0
		sh.wrap = false
		container.add_child(sh)
	for h in 2:
		var hx: float = -140.0 + float(h) * 40.0
		var hy: float = _h(root, Vector3(hx, 0, 150.0))
		GroundKit.box(root, Vector3(14.0, 5.0, 60.0), Vector3(hx, hy + 1.0, 150.0), Color(0.22, 0.2, 0.18), Vector3(0, float(h) * 30.0 - 20.0, 0))
		GroundKit.box(root, Vector3(10.0, 4.0, 16.0), Vector3(hx, hy + 3.5, 140.0), Color(0.18, 0.16, 0.15), Vector3.ZERO, false)
	return container


## River quay: a masonry quay wall along a river bank with wharf sheds and coal staithes on the land side and
## barges moored along the wall. `dir` is the unit direction the quay runs, i.e. ALONG the river bank.
static func build_river_quay(pos: Vector3, dir: Vector3, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(WorldCoords.dir_to_heading(dir))      # local -Z runs ALONG the river bank
	container.add_child(root)
	# decide which local X side faces the water
	var sea_w: Vector3 = GroundKit.water_dir(pos, 300.0)
	var wside: float = -1.0
	if sea_w != Vector3.ZERO:
		var local_sea: Vector3 = root.transform.basis.inverse() * sea_w
		wside = 1.0 if local_sea.x >= 0.0 else -1.0
	var k: float = 0.8 + 0.4 * float(size)
	var length: float = 260.0 * k
	var conc: Color = GroundKit.COL_CONCRETE
	var wood: Color = GroundKit.COL_WOOD
	var brick: Color = GroundKit.COL_BRICK.darkened(0.08)
	# quay wall (river side) + top slab + coping
	GroundKit.box(root, Vector3(26.0, 8.0, length), Vector3(wside * 13.0, -2.4, 0.0), conc.darkened(0.18))
	GroundKit.box(root, Vector3(30.0, 1.4, length), Vector3(wside * 13.0, 2.2, 0.0), conc.darkened(0.05))
	GroundKit.box(root, Vector3(3.0, 0.8, length), Vector3(wside * 27.0, 2.9, 0.0), Color(0.4, 0.4, 0.38), Vector3.ZERO, false)
	# wharf sheds and coal staithes on the land side (opposite the water)
	var land: float = -wside
	var sheds: int = 3 + size
	for i in sheds:
		var sz: float = (float(i) - float(sheds - 1) * 0.5) * (length / float(sheds) * 0.9)
		var sx: float = land * rng.randf_range(30.0, 60.0)
		var gy: float = _h(root, Vector3(sx, 0, sz))
		var sw: float = rng.randf_range(18.0, 30.0)
		var sl2: float = rng.randf_range(30.0, 60.0)
		GroundKit.box(root, Vector3(sw, 8.0, sl2), Vector3(sx, gy + 4.0, sz), brick if i % 2 == 0 else Color(0.55, 0.52, 0.45))
		var roof := MeshInstance3D.new()
		roof.mesh = GroundKit.prism_mesh(sw + 1.0, sl2 + 1.0, 3.4)
		roof.material_override = GroundKit.mat(Color(0.3, 0.29, 0.3), true)
		roof.position = Vector3(sx, gy + 8.0, sz)
		root.add_child(roof)
		# coal staithes: an inclined timber chute spilling over the wall to the barges
		if i % 2 == 1:
			GroundKit.box(root, Vector3(9.0, 0.8, 0.8), Vector3(wside * 22.0, 6.0, sz), wood, Vector3(0, 0, -land * 28.0), false)
			GroundKit.box(root, Vector3(6.0, 5.0, 8.0), Vector3(land * 44.0, gy + 2.5, sz), Color(0.16, 0.15, 0.14))
			GroundKit.cyl(root, 0.4, 0.5, 8.0, Vector3(land * 44.0, gy + 8.0, sz), Color(0.25, 0.24, 0.22), Vector3.ZERO, 6, false)
	# a couple of hand cranes on the quay edge
	for i in 2:
		var cz: float = (float(i) - 0.5) * length * 0.5
		GroundKit.cyl(root, 1.2, 1.6, 12.0, Vector3(wside * 20.0, 8.0, cz), Color(0.32, 0.32, 0.34), Vector3.ZERO, 8)
		GroundKit.box(root, Vector3(16.0, 1.4, 1.4), Vector3(wside * 12.0, 14.0, cz), Color(0.32, 0.32, 0.34), Vector3.ZERO, false)
	# barges moored along the wall
	var dumb: Color = Color(0.24, 0.22, 0.2)
	for i in 2 + size:
		var bz: float = (float(i) - float(1 + size) * 0.5) * 46.0
		var bx: float = wside * 34.0
		GroundKit.box(root, Vector3(9.0, 3.2, 40.0), Vector3(bx, 0.4, bz), dumb)
		GroundKit.box(root, Vector3(7.0, 1.6, 8.0), Vector3(bx, 2.6, bz + 12.0), Color(0.5, 0.46, 0.4))
	return container


## Small fishing harbour: a short stone quay with a slipway, a stub breakwater with a light, net lofts, an ice
## house, a boat store and a handful of inshore boats - the silhouette of a size-1 town, not a major dock.
static func build_fishing_harbour(pos: Vector3, sea: Vector3, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = -deg_to_rad(WorldCoords.dir_to_heading(sea))      # local -Z = towards the sea
	container.add_child(root)
	var k: float = 1.0 + 0.4 * float(size)
	var stone := Color(0.45, 0.45, 0.42)
	var conc: Color = GroundKit.COL_CONCRETE
	var wood: Color = GroundKit.COL_WOOD
	# stone quay along the shore + concrete coping
	GroundKit.box(root, Vector3(120.0 * k, 3.0, 26.0), Vector3(0, 1.0, 0.0), stone)
	GroundKit.box(root, Vector3(124.0 * k, 1.0, 28.0), Vector3(0, 2.6, 0.0), conc.darkened(0.1))
	# stub breakwater arm with a harbour light
	GroundKit.box(root, Vector3(14.0, 4.4, 74.0 * k), Vector3(-52.0 * k, 1.3, -52.0 * k), stone)
	GroundKit.cyl(root, 0.22, 0.28, 7.0, Vector3(-52.0 * k, 6.4, -88.0 * k), Color(0.9, 0.9, 0.86), Vector3.ZERO, 6, false)
	GroundKit.cyl(root, 1.3, 1.3, 2.0, Vector3(-52.0 * k, 11.0, -88.0 * k), Color(0.95, 0.9, 0.55), Vector3.ZERO, 8, false)
	# slipway down into the water
	GroundKit.box(root, Vector3(22.0, 1.0, 48.0), Vector3(40.0 * k, 0.9, -18.0), conc, Vector3(10.0, 0, 0))
	# net lofts: low timber sheds with long sloping roofs along the back of the quay
	for i in 3 + size:
		var nx: float = (float(i) - float(2 + size) * 0.5) * 22.0
		var nz: float = rng.randf_range(20.0, 34.0)
		var gy: float = _h(root, Vector3(nx, 0, nz))
		GroundKit.box(root, Vector3(16.0, 5.0, 9.0), Vector3(nx, gy + 2.5, nz), wood)
		var lo := MeshInstance3D.new()
		lo.mesh = GroundKit.prism_mesh(17.0, 10.0, 3.0)
		lo.material_override = GroundKit.mat(wood.darkened(0.25), true)
		lo.position = Vector3(nx, gy + 5.0, nz)
		root.add_child(lo)
	# ice house: a small whitewashed block with a chimney
	var ihx: float = -70.0 * k
	var ihy: float = _h(root, Vector3(ihx, 0, 40.0))
	GroundKit.box(root, Vector3(20.0, 7.0, 16.0), Vector3(ihx, ihy + 3.5, 40.0), Color(0.85, 0.84, 0.78))
	GroundKit.box(root, Vector3(21.0, 1.2, 17.0), Vector3(ihx, ihy + 7.2, 40.0), Color(0.35, 0.35, 0.37), Vector3.ZERO, false)
	GroundKit.cyl(root, 0.8, 1.0, 10.0, Vector3(ihx + 8.0, ihy + 5.0, 40.0), Color(0.5, 0.48, 0.44), Vector3.ZERO, 8)
	# harbour office / boat store
	var ofx: float = 66.0 * k
	var ofy: float = _h(root, Vector3(ofx, 0, 30.0))
	GroundKit.box(root, Vector3(14.0, 6.0, 12.0), Vector3(ofx, ofy + 3.0, 30.0), Color(0.5, 0.4, 0.3))
	# bollards along the quay edge
	for i in 8:
		GroundKit.cyl(root, 0.32, 0.4, 1.4, Vector3((float(i) - 3.5) * 14.0, 3.0, -11.0), GroundKit.COL_DARK, Vector3.ZERO, 6, false)
	# a few inshore boats moored along the quay
	var along: Vector3 = (root.transform.basis * Vector3(0, 0, -1)).normalized()
	var ship_n: int = 2 + size
	for i in ship_n:
		var wp: Vector3 = root.transform * Vector3(rng.randf_range(-50.0, 50.0) * k, 0, -rng.randf_range(16.0, 40.0))
		var rp: RoutePath = RoutePath.from_points(PackedVector3Array([wp, wp + along * 6.0]))
		var sh: GroundShip = GroundShip.create("fishing_boat", team, rp, 0.0, 0.0)
		sh.speed = 0.0
		sh.wrap = false
		container.add_child(sh)
	return container


# ============================================================================ camps
static func _truck_mesh(c: Color) -> ArrayMesh:
	var key: String = "ftruck_" + c.to_html(false)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var parts: Array = [
		GroundKit.box_part(Vector3(2.0, 1.5, 1.7), Vector3(0, 1.4, -2.0), c, Vector3.ZERO, false),
		GroundKit.box_part(Vector3(2.2, 0.3, 4.2), Vector3(0, 0.8, 1.0), c.darkened(0.5), Vector3.ZERO, false),
		GroundKit.box_part(Vector3(2.2, 1.6, 3.8), Vector3(0, 1.8, 1.1), c.lerp(Color(0.5, 0.45, 0.3), 0.5), Vector3.ZERO, false),
	]
	var m: ArrayMesh = GroundKit.combine(parts)
	_mesh_cache[key] = m
	return m


static func _tent_mesh(c: Color) -> ArrayMesh:
	var key: String = "tent_" + c.to_html(false)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 2.4
	cm.height = 2.8
	cm.radial_segments = 6
	cm.rings = 1
	var m: ArrayMesh = GroundKit.combine([[cm, Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0)), GroundKit.mat(c, false)]])
	_mesh_cache[key] = m
	return m


## Barracks / army camp centred on pos. kind: "barracks" | "camp". Returns a container at the world origin.
static func build_camp(pos: Vector3, kind: String, size: int, team: String, seed_v: int) -> Node3D:
	var container := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var yaw: float = rng.randf() * PI
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = yaw
	container.add_child(root)          # root carries the fence, flagpole, guard towers etc.
	var tf: Transform3D = root.transform
	var cy: float = GroundKit.ground_y(pos.x, pos.z)
	var allies: bool = team == "Allies"
	var khaki: Color = Color(0.45, 0.43, 0.3) if allies else Color(0.4, 0.42, 0.38)
	var houses: Array = [[], [], [], []]
	var huts: Array = []
	var tents: Array = []
	var trucks: Array = []
	var fence: Array = []
	var w: float = 90.0 + 40.0 * float(size)        # camp half-extent scale
	var pw: float = 70.0 + 22.0 * float(size)       # parade/open ground half width
	var pl: float = 50.0 + 16.0 * float(size)

	# parade ground / open ground (flat dark gravel slab)
	GroundKit.box(root, Vector3(pw * 2.0, 0.3, pl * 2.0), Vector3(0, cy + 0.12, 0), Color(0.42, 0.38, 0.3), Vector3.ZERO, false)
	# flagpole + flag
	GroundKit.cyl(root, 0.15, 0.22, 20.0, Vector3(pw * 0.7, cy + 10.0, 0), Color(0.85, 0.85, 0.85), Vector3.ZERO, 6, false)
	GroundKit.box(root, Vector3(6.0, 3.6, 0.15), Vector3(pw * 0.7 + 3.1, cy + 18.0, 0), Color(0.1, 0.16, 0.5) if allies else Color(0.65, 0.1, 0.1), Vector3.ZERO, false)

	if kind == "barracks":
		# brick barrack blocks along the long sides and a guard house + mess at the ends
		var rows: int = 2 + size
		for side in [-1.0, 1.0]:
			for i in rows:
				var lx: float = (float(i) - float(rows - 1) * 0.5) * (pw * 2.0 / float(rows)) * 0.92
				var lz: float = side * (pl + 20.0)
				_house(houses, tf, Vector3(lx, 0, lz), 0.0, Vector3(rng.randf_range(34.0, 46.0), rng.randf_range(9.0, 11.0), 13.0), rng)
		# end blocks (headquarters / mess)
		_house(houses, tf, Vector3(-pw - 26.0, 0, 0), PI * 0.5, Vector3(40.0, 10.0, 16.0), rng)
		_house(houses, tf, Vector3(pw + 30.0, 0, rng.randf_range(-20.0, 20.0)), PI * 0.5, Vector3(26.0, 8.0, 12.0), rng)
		# motor pool: lines of lorries
		for i in 4 + size * 2:
			trucks.append(_xf_world(tf, Vector3(-pw * 0.5 + float(i % 6) * 9.0, 0, pl + 62.0 + float(i / 6) * 16.0), PI * 0.5 + rng.randf_range(-0.05, 0.05), Vector3.ONE * 1.1))
	else:
		# camp: rows of Nissen huts, tent lines, field kitchens and a lorry park
		var hut_rows: int = 3 + size
		var hut_cols: int = 5 + size * 3
		for r in hut_rows:
			for cc in hut_cols:
				var hx: float = (float(cc) - float(hut_cols - 1) * 0.5) * 8.2
				var hz: float = (float(r) - float(hut_rows - 1) * 0.5) * 17.0 + (pl + 34.0 + float(r) * 3.0)
				huts.append(_xf_world(tf, Vector3(hx, 0, hz), PI * 0.5, Vector3(1.0, 1.0, 1.0) * 1.15))
		var tent_n: int = 20 + 22 * size
		for i in tent_n:
			var tcol: int = i % 5
			var tx: float = (float(i % 12) - 5.5) * 6.0
			var tz: float = -(pl + 24.0) - float(i / 12) * 8.0
			tents.append(_xf_world(tf, Vector3(tx + rng.randf_range(-0.6, 0.6), 0, tz), rng.randf() * TAU, Vector3(1.0, rng.randf_range(0.85, 1.1), 1.0) * 1.1))
			if tcol == 99:
				pass
		for i in 4 + size * 3:
			trucks.append(_xf_world(tf, Vector3(-pw * 0.8 + float(i % 7) * 10.0, 0, -(pl + 78.0) - float(i / 7) * 14.0), rng.randf_range(-0.1, 0.1), Vector3.ONE * 1.1))
		_house(houses, tf, Vector3(pw + 30.0, 0, -10.0), PI * 0.5, Vector3(30.0, 7.0, 12.0), rng)   # mess hall
		_house(houses, tf, Vector3(-pw - 28.0, 0, 14.0), PI * 0.5, Vector3(22.0, 6.5, 10.0), rng)   # stores / HQ

	# perimeter fence: panels of wire/timber around the whole site (leaving a gap for the gate)
	var fx: float = pw + 70.0
	var fz: float = pl + (110.0 if kind == "camp" else 90.0)
	for side in 4:
		var length: float = (fx * 2.0) if side < 2 else (fz * 2.0)
		var n: int = int(length / 22.0)
		for i in n:
			var t: float = (float(i) + 0.5) / float(n) - 0.5
			var local: Vector3
			var yw: float
			match side:
				0:
					local = Vector3(t * length, 0, -fz)
					yw = 0.0
				1:
					local = Vector3(t * length, 0, fz)
					yw = 0.0
				2:
					local = Vector3(-fx, 0, t * length)
					yw = PI * 0.5
				_:
					local = Vector3(fx, 0, t * length)
					yw = PI * 0.5
			if side == 1 and absf(local.x) < 14.0:
				continue         # main gate
			fence.append(_xf_world(tf, local, yw, Vector3(22.0, 2.2, 0.25)))
	# gate house and guard towers
	GroundKit.box(root, Vector3(5.0, 3.2, 5.0), Vector3(16.0, cy + 1.6, fz), Color(0.5, 0.4, 0.3))
	GroundKit.box(root, Vector3(5.0, 3.2, 5.0), Vector3(-16.0, cy + 1.6, fz), Color(0.5, 0.4, 0.3))
	for cxs in [-1.0, 1.0]:
		for czs in [-1.0, 1.0]:
			var gx: float = cxs * fx
			var gz: float = czs * fz
			var gy: float = _h(root, Vector3(gx, 0, gz))
			GroundKit.cyl(root, 0.2, 0.3, 9.0, Vector3(gx, gy + 4.5, gz), GroundKit.COL_WOOD, Vector3.ZERO, 5, false)
			GroundKit.box(root, Vector3(3.2, 2.2, 3.2), Vector3(gx, gy + 10.0, gz), khaki.darkened(0.2))
			GroundKit.box(root, Vector3(3.9, 0.4, 3.9), Vector3(gx, gy + 11.4, gz), GroundKit.COL_DARK, Vector3.ZERO, false)

	for i in 4:
		if not (houses[i] as Array).is_empty():
			container.add_child(Scatter.multi(Scatter.house_mesh(i), houses[i], 12000.0))
	if not huts.is_empty():
		container.add_child(Scatter.multi(Scatter.nissen_mesh(), huts, 11000.0))
	if not tents.is_empty():
		container.add_child(Scatter.multi(_tent_mesh(Color(0.58, 0.55, 0.4) if allies else Color(0.45, 0.47, 0.4)), tents, 9000.0))
	if not trucks.is_empty():
		container.add_child(Scatter.multi(_truck_mesh(khaki), trucks, 8000.0))
	if not fence.is_empty():
		container.add_child(Scatter.multi(Scatter.box_unit(Color(0.3, 0.27, 0.2), false), fence, 6000.0))
	return container


## Brick barrack block (uses the textured house mesh scaled to a long building).
static func _house(lists: Array, tf: Transform3D, local: Vector3, yaw_local: float, size_v: Vector3, rng: RandomNumberGenerator) -> void:
	var wp: Vector3 = tf * local
	var y: float = GroundKit.ground_y(wp.x, wp.z) + size_v.y * 0.5 - 0.4
	var yaw: float = atan2(tf.basis.z.x, tf.basis.z.z) + yaw_local
	(lists[rng.randi() % 4] as Array).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size_v), Vector3(wp.x, y, wp.z)))


static func _xf_world(tf: Transform3D, local: Vector3, yaw_local: float, scale_v: Vector3) -> Transform3D:
	var wp: Vector3 = tf * local
	var y: float = GroundKit.ground_y(wp.x, wp.z)
	return Transform3D(Basis(Vector3.UP, atan2(tf.basis.z.x, tf.basis.z.z) + yaw_local) * Basis.from_scale(scale_v), Vector3(wp.x, y + scale_v.y * (0.0 if scale_v.y < 2.0 else 0.5), wp.z))


## Sea marks of the Dover Strait and Thames Estuary: lightvessels on the shoals and the Maunsell sea forts.
## [id, name, lat, lon, kind]
const SEA_MARKS := [
	["lv_east_goodwin", "East Goodwin lightvessel", 51.2250, 1.6050, "lightship"],
	["lv_south_goodwin", "South Goodwin lightvessel", 51.1300, 1.4700, "lightship"],
	["lv_gull", "Gull lightvessel", 51.2700, 1.5100, "lightship"],
	["lv_varne", "Varne lightvessel", 51.0200, 1.4000, "lightship"],
	["lv_sandettie", "Sandettie lightvessel", 51.1500, 1.8000, "lightship"],
	["lv_royal_sovereign", "Royal Sovereign lightvessel", 50.7230, 0.4360, "lightship"],
	["lv_sunk", "Sunk lightvessel", 51.8500, 1.5900, "lightship"],
	["lv_cork", "Cork lightvessel", 51.9700, 1.9500, "lightship"],
	["lv_galloper", "Galloper lightvessel", 51.7500, 2.0000, "lightship"],
	["lv_noord_hinder", "Noord Hinder lightvessel", 51.5800, 2.4600, "lightship"],
	["lv_schouwenbank", "Schouwenbank lightvessel", 51.7200, 3.0000, "lightship"],
	["lv_shipwash", "Shipwash lightvessel", 52.0400, 1.7400, "lightship"],
	["lv_smiths_knoll", "Smith's Knoll lightvessel", 52.7200, 2.3000, "lightship"],
	["lv_haisborough", "Haisborough lightvessel", 52.9000, 1.9500, "lightship"],
	["fort_shivering_sands", "Shivering Sands Army Fort", 51.4990, 1.0750, "army_fort"],
	["fort_red_sands", "Red Sands Army Fort", 51.4770, 0.9940, "army_fort"],
	["fort_tongue_sands", "Tongue Sands Navy Fort", 51.4930, 1.2430, "navy_fort"],
	["fort_knock_john", "Knock John Navy Fort", 51.5600, 1.1650, "navy_fort"],
]


## Red-hulled lightvessel at anchor: lantern on a lattice mast amidships, name painted on the side.
static func build_lightship() -> Node3D:
	var root := Node3D.new()
	var red := Color(0.72, 0.14, 0.1)
	GroundKit.box(root, Vector3(7.5, 3.2, 28.0), Vector3(0, 0.6, 0), red)
	GroundKit.box(root, Vector3(6.6, 1.2, 6.0), Vector3(0, 1.6, -13.0), red, Vector3(-12, 0, 0))
	GroundKit.box(root, Vector3(4.0, 2.2, 6.0), Vector3(0, 3.3, 5.0), Color(0.86, 0.84, 0.78))
	GroundKit.cyl(root, 0.35, 0.5, 14.0, Vector3(0, 9.0, -2.0), Color(0.82, 0.8, 0.74), Vector3.ZERO, 6)
	GroundKit.cyl(root, 1.6, 1.6, 2.4, Vector3(0, 16.5, -2.0), Color(0.95, 0.9, 0.55), Vector3.ZERO, 8, false)
	GroundKit.cyl(root, 0.0, 1.9, 1.4, Vector3(0, 18.4, -2.0), Color(0.15, 0.15, 0.16), Vector3.ZERO, 8)
	GroundKit.cyl(root, 0.2, 0.25, 8.0, Vector3(0, 6.0, 10.0), Color(0.3, 0.3, 0.3), Vector3.ZERO, 5)
	return root


## Maunsell fort. Army forts: seven square steel towers on four legs joined by catwalks (a gun-site
## layout); navy forts: one large two-legged concrete pontoon with a deck and AA guns.
static func build_sea_fort(kind: String) -> Node3D:
	var root := Node3D.new()
	var steel := Color(0.42, 0.42, 0.4)
	var rust := Color(0.45, 0.3, 0.2)
	if kind == "navy_fort":
		for sx in [-1.0, 1.0]:
			GroundKit.cyl(root, 4.2, 4.6, 22.0, Vector3(sx * 9.0, 9.0, 0), Color(0.6, 0.6, 0.56), Vector3.ZERO, 12)
		GroundKit.box(root, Vector3(34.0, 4.0, 16.0), Vector3(0, 22.0, 0), steel)
		GroundKit.box(root, Vector3(12.0, 4.0, 8.0), Vector3(-6.0, 26.0, 0), Color(0.5, 0.5, 0.47))
		for gx in [-13.0, 11.0]:
			GroundKit.cyl(root, 1.8, 2.0, 1.4, Vector3(gx, 24.7, 3.0), rust, Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.18, 0.18, 5.0, Vector3(gx, 26.2, 5.0), GroundKit.COL_DARK, Vector3(60, 0, 0), 5, false)
		return root
	# army fort: control tower in the middle, guns round it, searchlight tower off to one side
	var spots: Array = [Vector2(0, 0), Vector2(-38, -22), Vector2(38, -22), Vector2(-38, 22), Vector2(38, 22), Vector2(0, -44), Vector2(0, 58)]
	for i in spots.size():
		var s: Vector2 = spots[i]
		for lx in [-3.5, 3.5]:
			for lz in [-3.5, 3.5]:
				GroundKit.cyl(root, 0.5, 0.6, 20.0, Vector3(s.x + lx, 8.0, s.y + lz), rust, Vector3.ZERO, 5, false)
		GroundKit.box(root, Vector3(10.0, 9.0, 10.0), Vector3(s.x, 22.5, s.y), steel)
		GroundKit.box(root, Vector3(11.0, 0.6, 11.0), Vector3(s.x, 27.3, s.y), steel.darkened(0.2))
		if i >= 1 and i <= 4:
			GroundKit.cyl(root, 1.6, 1.8, 1.4, Vector3(s.x, 28.3, s.y), Color(0.36, 0.38, 0.32), Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.16, 0.16, 5.0, Vector3(s.x, 29.4, s.y + 2.2), GroundKit.COL_DARK, Vector3(60, 0, 0), 5, false)
		if i > 0:
			var mid: Vector2 = (s + spots[0]) * 0.5
			var ln: float = s.distance_to(spots[0])
			var ang: float = rad_to_deg(atan2(s.x, s.y))
			GroundKit.box(root, Vector3(1.2, 0.8, ln - 10.0), Vector3(mid.x, 24.0, mid.y), Color(0.3, 0.3, 0.3), Vector3(0, ang, 0), false)
	return root
