class_name Landmarks
extends RefCounted
## Procedural low-poly landmarks (exaggerated in scale so they read from the air).
## Landmarks.build(feature_id) -> Node3D or null.  Also church() and windmill().


static func _b(root: Node3D, size: Vector3, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, outline: bool = true) -> MeshInstance3D:
	return GroundKit.box(root, size, pos, color, rot, outline)


static func church(s: float = 1.0) -> Node3D:
	var root := Node3D.new()
	var stone := Color(0.62, 0.58, 0.5)
	_b(root, Vector3(10, 9, 24), Vector3(0, 4.5, 0), stone)
	var roof := MeshInstance3D.new()
	roof.mesh = GroundKit.prism_mesh(11.5, 25.0, 4.5)
	roof.material_override = GroundKit.mat(Color(0.3, 0.28, 0.3), true)
	roof.position = Vector3(0, 9.0, 0)
	root.add_child(roof)
	_b(root, Vector3(6, 22, 6), Vector3(0, 11, 12), stone)
	var spire := GroundKit.cyl(root, 0.0, 4.4, 14.0, Vector3(0, 29.0, 12), Color(0.34, 0.36, 0.4), Vector3.ZERO, 4)
	spire.rotation.y = PI * 0.25
	root.scale = Vector3.ONE * s
	return root


static func windmill() -> Node3D:
	var root := Node3D.new()
	GroundKit.cyl(root, 3.0, 5.0, 16.0, Vector3(0, 8, 0), Color(0.72, 0.68, 0.58), Vector3.ZERO, 8)
	GroundKit.cyl(root, 0.0, 4.0, 4.5, Vector3(0, 18.2, 0), Color(0.35, 0.25, 0.18), Vector3.ZERO, 8)
	var sails := Node3D.new()
	sails.position = Vector3(0, 15.0, -3.6)
	sails.name = "Sails"
	root.add_child(sails)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = float(i) * PI * 0.5
		sails.add_child(arm)
		GroundKit.box(arm, Vector3(1.8, 15.0, 0.3), Vector3(0, 8.0, 0), Color(0.82, 0.78, 0.68), Vector3.ZERO, false)
	sails.rotation.z = randf() * TAU
	return root


static func lighthouse(h: float = 40.0) -> Node3D:
	var root := Node3D.new()
	GroundKit.cyl(root, 3.0, 5.0, h, Vector3(0, h * 0.5, 0), Color(0.88, 0.86, 0.82), Vector3.ZERO, 10)
	GroundKit.cyl(root, 3.2, 3.2, 3.0, Vector3(0, h * 0.35, 0), Color(0.7, 0.15, 0.12), Vector3.ZERO, 10)
	GroundKit.cyl(root, 2.6, 2.6, 4.0, Vector3(0, h + 2.0, 0), Color(0.9, 0.85, 0.5), Vector3.ZERO, 8, false)
	GroundKit.cyl(root, 0.0, 3.4, 3.0, Vector3(0, h + 5.5, 0), Color(0.2, 0.2, 0.22), Vector3.ZERO, 8)
	return root


## Generic cathedral: nave with a pitched roof, transept, one or two west towers (optionally with spires) and an optional dome.
static func _cathedral(root: Node3D, nave_len: float, nave_w: float, tower_h: float, towers: int, spire_h: float, col: Color, dome: bool = false, ruin: bool = false) -> void:
	var dark := Color(0.3, 0.3, 0.34)
	var wall_h: float = tower_h * 0.28
	_b(root, Vector3(nave_w, wall_h, nave_len), Vector3(0, wall_h * 0.5, 0), col)
	if not ruin:
		var roof := MeshInstance3D.new()
		roof.mesh = GroundKit.prism_mesh(nave_w * 1.1, nave_len * 1.02, tower_h * 0.16)
		roof.material_override = GroundKit.mat(Color(0.3, 0.3, 0.34), true)
		roof.position = Vector3(0, wall_h, 0)
		root.add_child(roof)
	_b(root, Vector3(nave_w * 1.7, wall_h * 0.95, nave_len * 0.16), Vector3(0, wall_h * 0.48, nave_len * 0.05), col)
	for i in towers:
		var x: float = 0.0 if towers == 1 else (-nave_w * 0.3 if i == 0 else nave_w * 0.3)
		var z: float = nave_len * 0.5 - nave_w * 0.18
		_b(root, Vector3(nave_w * 0.34, tower_h, nave_w * 0.34), Vector3(x, tower_h * 0.5, z), col)
		if spire_h > 0.0:
			GroundKit.cyl(root, 0.0, nave_w * 0.22, spire_h, Vector3(x, tower_h + spire_h * 0.5, z), dark, Vector3.ZERO, 4)
	if dome:
		GroundKit.sphere(root, nave_w * 0.5, Vector3(0, wall_h + nave_w * 0.25, nave_len * 0.05), Color(0.5, 0.58, 0.56), Vector3(1, 0.8, 1))


## Arch bridge (steel / stone): deck, a row of arch members with hangers and optional end towers.
## broken: the centre of the span has fallen (Ludendorff Bridge from 17 Mar 1945, Arnhem road bridge from 7 Oct
## 1944): the deck and arch stop short each side and the fallen girders lie in the river.
static func _arch_bridge(root: Node3D, span: float, rise: float, col: Color, towers: bool, broken: bool = false) -> void:
	var gap: float = span * 0.36 if broken else 0.0
	if broken:
		for sx in [-1.0, 1.0]:
			_b(root, Vector3((span - gap) * 0.5, 2.0, 9.0), Vector3(sx * (gap * 0.5 + (span - gap) * 0.25), 8.0, 0), Color(0.28, 0.28, 0.3))
		_b(root, Vector3(gap * 0.55, 2.0, 9.0), Vector3(-gap * 0.12, 1.2, 1.5), Color(0.26, 0.24, 0.24), Vector3(0, 6, -14))
		_b(root, Vector3(gap * 0.45, 1.6, 8.0), Vector3(gap * 0.2, 0.6, -2.0), col.darkened(0.2), Vector3(0, -9, 11))
	else:
		_b(root, Vector3(span, 2.0, 9.0), Vector3(0, 8.0, 0), Color(0.28, 0.28, 0.3))
	var n: int = 9
	for sz in [-1.0, 1.0]:
		for i in n:
			var t: float = float(i) / float(n - 1)
			var x: float = lerpf(-span * 0.5, span * 0.5, t)
			if broken and absf(x) < gap * 0.5:
				continue
			var y: float = 8.0 + rise * sin(PI * t)
			_b(root, Vector3(span / float(n - 1) * 1.15, 1.6, 1.6), Vector3(x, y, sz * 4.4), col, Vector3(0, 0, rad_to_deg(atan2(PI * rise * cos(PI * t) / span, 1.0))))
			if i % 2 == 0 and y > 10.0:
				_b(root, Vector3(0.6, y - 8.0, 0.6), Vector3(x, 8.0 + (y - 8.0) * 0.5, sz * 4.4), col)
	if towers:
		for sx in [-1.0, 1.0]:
			_b(root, Vector3(10, 26, 12), Vector3(sx * (span * 0.5 + 6.0), 13, 0), Color(0.5, 0.48, 0.44))
			GroundKit.cyl(root, 0.0, 7.0, 9.0, Vector3(sx * (span * 0.5 + 6.0), 30.5, 0), Color(0.3, 0.3, 0.34), Vector3.ZERO, 4)


## P14 seaside landmarks ---------------------------------------------------------------------------
## A Martello tower: a squat, battered round masonry tower with a flat parapeted gun platform, a ring of
## embrasures and a low doorway. `s` scales it (the Kent/Sussex coast towers are ~10 m).
static func _martello(root: Node3D, s: float = 1.0) -> void:
	var stone := Color(0.66, 0.62, 0.54)
	GroundKit.cyl(root, 7.0, 8.6, 9.5, Vector3(0, 4.75, 0), stone, Vector3.ZERO, 14)
	GroundKit.cyl(root, 8.8, 8.8, 1.4, Vector3(0, 10.2, 0), stone.darkened(0.08), Vector3.ZERO, 14)   # parapet
	_b(root, Vector3(15.2, 0.6, 15.2), Vector3(0, 9.5, 0), Color(0.6, 0.56, 0.48), Vector3.ZERO, false)  # gun platform
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		_b(root, Vector3(1.8, 0.7, 0.5), Vector3(sin(a) * 7.6, 8.4, cos(a) * 7.6), GroundKit.COL_DARK, Vector3(0, -rad_to_deg(a), 0), false)
	_b(root, Vector3(2.0, 3.0, 0.7), Vector3(0, 1.5, 8.4), GroundKit.COL_DARK, Vector3.ZERO, false)          # doorway
	_b(root, Vector3(11.0, 0.4, 11.0), Vector3(0, 0.2, 0), Color(0.5, 0.5, 0.44), Vector3.ZERO, false)       # base skirt
	root.scale = Vector3.ONE * s


## A coastguard station: a two-storey watch house with a gabled roof, a glazed lookout turret and a flagstaff,
## with a rocket / boathouse shed beside it (the 1940s HM Coastguard look-out posts of the Channel coast).
static func _coastguard_station(root: Node3D) -> void:
	var wall := Color(0.9, 0.89, 0.84)
	var roof := Color(0.32, 0.32, 0.34)
	_b(root, Vector3(16, 8, 10), Vector3(0, 4, 0), wall)
	var rh := MeshInstance3D.new()
	rh.mesh = GroundKit.prism_mesh(17.0, 11.0, 4.0)
	rh.material_override = GroundKit.mat(roof, true)
	rh.position = Vector3(0, 8, 0)
	root.add_child(rh)
	# substantial chimney and window band
	_b(root, Vector3(2, 3, 2), Vector3(-6.0, 9.5, 0), GroundKit.COL_BRICK)
	for sz in [-3.0, 3.0]:
		_b(root, Vector3(8.0, 1.3, 0.3), Vector3(0, 5.2, sz + 0.6), Color(0.24, 0.3, 0.32), Vector3.ZERO, false)
	# lookout turret on the seaward end
	GroundKit.cyl(root, 3.0, 3.2, 5.0, Vector3(9.0, 10.5, 0), wall)
	GroundKit.cyl(root, 3.2, 3.2, 0.6, Vector3(9.0, 13.2, 0), roof, Vector3.ZERO, 10, false)
	GroundKit.cyl(root, 2.4, 2.4, 2.2, Vector3(9.0, 12.0, 0), Color(0.3, 0.4, 0.44), Vector3.ZERO, 10, false)
	GroundKit.cyl(root, 0.12, 0.12, 8.0, Vector3(9.0, 17.5, 0), Color(0.6, 0.6, 0.58), Vector3.ZERO, 4, false)   # flagstaff
	_b(root, Vector3(3.0, 1.6, 0.1), Vector3(10.6, 20.4, 0), Color(0.85, 0.2, 0.18), Vector3.ZERO, false)          # ensign
	# rocket / boathouse shed
	_b(root, Vector3(12, 5, 8), Vector3(-16, 2.5, 2), Color(0.86, 0.85, 0.8))
	var sh := MeshInstance3D.new()
	sh.mesh = GroundKit.prism_mesh(13.0, 9.0, 3.0)
	sh.material_override = GroundKit.mat(roof, true)
	sh.position = Vector3(-16, 5, 2)
	root.add_child(sh)


## An RNLI lifeboat station: an open boathouse with a wide door, a launching slipway running out (local -Z,
## towards the sea), a crew / lookout room and a lifebuoy on a post (the 1940s coastal lifeboat stations).
static func _lifeboat_station(root: Node3D) -> void:
	var wall := Color(0.84, 0.83, 0.78)
	var roof := Color(0.3, 0.3, 0.32)
	_b(root, Vector3(18, 7, 12), Vector3(0, 3.5, 4), wall)
	var bh := MeshInstance3D.new()
	bh.mesh = GroundKit.prism_mesh(19.0, 13.0, 4.0)
	bh.material_override = GroundKit.mat(roof, true)
	bh.position = Vector3(0, 7, 4)
	root.add_child(bh)
	_b(root, Vector3(11, 6, 0.6), Vector3(0, 3, -2.2), Color(0.16, 0.16, 0.17), Vector3.ZERO, false)        # boathouse doors
	# launch slipway running out to sea
	_b(root, Vector3(14, 0.8, 34), Vector3(0, 0.4, -19), Color(0.5, 0.5, 0.46), Vector3(9, 0, 0), false)
	for sz in [-1.0, 1.0]:
		_b(root, Vector3(1.0, 1.6, 34), Vector3(sz * 7.0, 1.0, -19), Color(0.42, 0.42, 0.38), Vector3(6, 0, 0), false)
	# crew room / lookout
	_b(root, Vector3(8, 5, 7), Vector3(15, 2.5, 6), wall.darkened(0.05))
	_b(root, Vector3(9, 1.0, 8), Vector3(15, 5.2, 6), roof, Vector3.ZERO, false)
	# lifebuoy post
	GroundKit.cyl(root, 0.2, 0.25, 3.0, Vector3(-12, 1.5, 0), GroundKit.COL_WOOD, Vector3.ZERO, 6, false)
	GroundKit.cyl(root, 1.2, 1.2, 0.4, Vector3(-12, 3.0, 0), Color(0.9, 0.9, 0.9), Vector3(90, 0, 0), 10, false)


## A 1930s lido: an open-air pool in a paved terrace, with diving boards, steps, a fountain and a changing-room
## block - the seaside lidos commandeered as military training / recreation in the war years.
static func _lido(root: Node3D) -> void:
	var conc := Color(0.8, 0.78, 0.72)
	var deck := conc.darkened(0.08)
	_b(root, Vector3(46, 0.5, 26), Vector3(0, 0.25, 0), deck, Vector3.ZERO, false)                       # paved terrace
	var water: MeshInstance3D = _b(root, Vector3(36, 0.4, 18), Vector3(0, 0.35, 0), Color(0.2, 0.5, 0.62), Vector3.ZERO, false)
	water.material_override = GroundKit.glow_mat(Color(0.2, 0.5, 0.62), 0.9, false)
	for sz in [-10.0, 10.0]:
		_b(root, Vector3(38, 0.9, 1.4), Vector3(0, 0.6, sz), conc.darkened(0.12), Vector3.ZERO, false)    # coping
	# changing rooms along the landward (south) side
	_b(root, Vector3(46, 5, 8), Vector3(0, 2.5, 16), conc)
	_b(root, Vector3(47, 0.8, 9), Vector3(0, 5.2, 16), Color(0.5, 0.5, 0.48), Vector3.ZERO, false)
	for i in 8:
		_b(root, Vector3(0.4, 3.0, 0.4), Vector3(-20.0 + float(i) * 5.7, 3.5, 12.2), conc.darkened(0.2), Vector3.ZERO, false)
	# high and low diving boards on the seaward (north) side
	for bx in [-8.0, 8.0]:
		GroundKit.cyl(root, 0.5, 0.6, 2.4, Vector3(bx, 1.7, -11.0), conc.darkened(0.1), Vector3.ZERO, 8)
		_b(root, Vector3(3.0, 0.3, 6.0), Vector3(bx, 2.9, -8.4), conc, Vector3.ZERO, false)
	GroundKit.cyl(root, 0.6, 0.7, 6.5, Vector3(0, 3.7, -11.0), conc.darkened(0.1), Vector3.ZERO, 8)
	_b(root, Vector3(3.4, 0.3, 7.0), Vector3(0, 7.2, -8.0), conc, Vector3.ZERO, false)
	# fountain jet in the middle of the pool
	GroundKit.cyl(root, 0.5, 0.9, 1.0, Vector3(0, 0.9, 0), conc)
	GroundKit.cyl(root, 0.15, 0.3, 3.0, Vector3(0, 2.6, 0), Color(0.8, 0.9, 0.95), Vector3.ZERO, 6, false)


## A promenade bandstand: a raised octagonal platform on slim columns under a shallow metal dome with a finial,
## ringed by a railing, with a short flight of steps - the Victorian / Edwardian seaside bandstand.
static func _bandstand(root: Node3D) -> void:
	var iron := Color(0.16, 0.26, 0.24)
	var deck := Color(0.62, 0.6, 0.54)
	GroundKit.cyl(root, 8.0, 8.6, 1.2, Vector3(0, 0.6, 0), deck, Vector3.ZERO, 14)
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		GroundKit.cyl(root, 0.22, 0.22, 6.0, Vector3(sin(a) * 6.6, 4.2, cos(a) * 6.6), iron, Vector3.ZERO, 6, false)
		# pierced valance around the eaves
	_b(root, Vector3(17.0, 0.5, 0.4), Vector3(0, 7.4, 7.4), iron, Vector3.ZERO, false)
	_b(root, Vector3(0.4, 0.5, 17.0), Vector3(7.4, 7.4, 0), iron, Vector3.ZERO, false)
	GroundKit.sphere(root, 9.0, Vector3(0, 7.2, 0), Color(0.28, 0.34, 0.32), Vector3(1.0, 0.5, 1.0))       # dome
	GroundKit.cyl(root, 0.0, 0.8, 2.2, Vector3(0, 12.0, 0), iron, Vector3.ZERO, 6, false)                    # finial
	# steps and railing
	_b(root, Vector3(5.0, 0.4, 3.0), Vector3(0, 0.2, 9.0), deck, Vector3.ZERO, false)
	for sz in [-7.6, 7.6]:
		_b(root, Vector3(16.0, 0.18, 0.18), Vector3(0, 1.4, sz), iron, Vector3.ZERO, false)


## A requisitioned seaside holiday camp: rows of small chalets around a central hall / dining block with a
## flagstaff and a gatehouse - the Butlin's-style camps taken over as military camps in 1940.
static func _holiday_camp(root: Node3D) -> void:
	var chalet := Color(0.72, 0.62, 0.42)
	var roof := Color(0.34, 0.3, 0.24)
	for r in 4:
		for c in 6:
			var cx: float = float(c) * 12.0 - 30.0
			var cz: float = float(r) * 14.0 - 6.0
			if r < 2 and (c == 2 or c == 3):
				continue                                   # leave room for the hall
			_b(root, Vector3(8.0, 3.0, 5.0), Vector3(cx, 1.5, cz), chalet.lightened(0.04 * float((r + c) % 3)))
			var cr := MeshInstance3D.new()
			cr.mesh = GroundKit.prism_mesh(8.6, 5.6, 2.0)
			cr.material_override = GroundKit.mat(roof, true)
			cr.position = Vector3(cx, 3.0, cz)
			root.add_child(cr)
	# central hall / dining block
	_b(root, Vector3(30, 8, 16), Vector3(0, 4, 20), Color(0.78, 0.72, 0.58))
	_b(root, Vector3(31, 1.2, 17), Vector3(0, 8.5, 20), roof, Vector3.ZERO, false)
	# gatehouse and flagstaff at the entrance (local -Z)
	_b(root, Vector3(6, 5, 5), Vector3(-14, 2.5, -30), chalet.darkened(0.06))
	GroundKit.cyl(root, 0.15, 0.2, 12.0, Vector3(6, 6.0, -28), Color(0.6, 0.6, 0.58), Vector3.ZERO, 4, false)
	_b(root, Vector3(4.0, 2.0, 0.1), Vector3(8.2, 10.5, -28), Color(0.2, 0.4, 0.7), Vector3.ZERO, false)


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	var stone := Color(0.64, 0.6, 0.52)
	var dark := Color(0.3, 0.3, 0.34)
	match id:
		"big_ben":
			_b(root, Vector3(14, 10, 14), Vector3(0, 5, 0), stone)
			_b(root, Vector3(11, 60, 11), Vector3(0, 40, 0), stone)
			_b(root, Vector3(13, 13, 13), Vector3(0, 76, 0), Color(0.7, 0.66, 0.55))
			for a in [0.0, 90.0]:
				GroundKit.cyl(root, 4.6, 4.6, 13.4, Vector3(0, 76, 0), Color(0.95, 0.93, 0.8), Vector3(90, a, 0), 12, false)
			GroundKit.cyl(root, 0.0, 8.0, 22.0, Vector3(0, 93.5, 0), dark, Vector3.ZERO, 4)
			_b(root, Vector3(70, 14, 20), Vector3(-50, 7, 0), Color(0.68, 0.62, 0.48))       # Parliament
			for i in 5:
				GroundKit.cyl(root, 0.0, 3.0, 8.0, Vector3(-75.0 + float(i) * 14.0, 18, 0), dark, Vector3.ZERO, 4)
		"tower_bridge":
			for sx in [-1.0, 1.0]:
				_b(root, Vector3(14, 56, 14), Vector3(sx * 40.0, 28, 0), Color(0.55, 0.6, 0.66))
				GroundKit.cyl(root, 0.0, 10.0, 16.0, Vector3(sx * 40.0, 64, 0), dark, Vector3.ZERO, 4)
			_b(root, Vector3(66, 3, 10), Vector3(0, 46, 0), Color(0.3, 0.45, 0.62))           # high walkway
			_b(root, Vector3(40, 3, 12), Vector3(0, 28, 0), Color(0.3, 0.3, 0.34))
			_b(root, Vector3(60, 3, 12), Vector3(-80, 26, 0), Color(0.3, 0.3, 0.34))
			_b(root, Vector3(60, 3, 12), Vector3(80, 26, 0), Color(0.3, 0.3, 0.34))
		"dover_castle":
			_b(root, Vector3(90, 8, 70), Vector3(0, 4, 0), Color(0.7, 0.68, 0.6))
			_b(root, Vector3(24, 26, 24), Vector3(0, 21, 0), stone)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 4.5, 5.0, 18.0, Vector3(sx * 45.0, 9, sz * 35.0), stone, Vector3.ZERO, 8)
					GroundKit.cyl(root, 0.0, 5.5, 5.0, Vector3(sx * 45.0, 20.5, sz * 35.0), dark, Vector3.ZERO, 8)
			_b(root, Vector3(26, 3, 26), Vector3(0, 35, 0), Color(0.58, 0.55, 0.5))
		"st_pauls":
			_b(root, Vector3(40, 16, 70), Vector3(0, 8, 0), Color(0.78, 0.75, 0.68))
			GroundKit.cyl(root, 14.0, 15.0, 14.0, Vector3(0, 23, 0), Color(0.78, 0.75, 0.68), Vector3.ZERO, 14)
			GroundKit.sphere(root, 15.0, Vector3(0, 30, 0), Color(0.55, 0.6, 0.58), Vector3(1, 0.8, 1))
			GroundKit.cyl(root, 0.0, 1.8, 10.0, Vector3(0, 48, 0), dark, Vector3.ZERO, 6)
			for sz in [-1.0, 1.0]:
				_b(root, Vector3(10, 36, 10), Vector3(0, 18, sz * 40.0), Color(0.75, 0.72, 0.65))
		"mont_saint_michel":
			GroundKit.cyl(root, 12.0, 52.0, 56.0, Vector3(0, 28, 0), Color(0.5, 0.46, 0.4), Vector3.ZERO, 10)
			for k in 8:
				var a: float = TAU * float(k) / 8.0
				_b(root, Vector3(10, 6.0, 8), Vector3(cos(a) * 24.0, 12.0 + float(k % 3) * 7.0, sin(a) * 24.0), Color(0.64, 0.6, 0.52), Vector3(0, -rad_to_deg(a), 0))
			_b(root, Vector3(18, 14, 28), Vector3(0, 63, 0), stone)
			GroundKit.cyl(root, 0.0, 3.5, 34.0, Vector3(0, 87, 0), dark, Vector3.ZERO, 6)
		"beffroi_calais":
			_b(root, Vector3(14, 54, 14), Vector3(0, 27, 0), Color(0.62, 0.38, 0.3))
			_b(root, Vector3(18, 9, 18), Vector3(0, 58, 0), Color(0.68, 0.64, 0.56))
			GroundKit.cyl(root, 0.0, 10.0, 18.0, Vector3(0, 71, 0), dark, Vector3.ZERO, 4)
			_b(root, Vector3(50, 16, 24), Vector3(-34, 8, 0), Color(0.66, 0.6, 0.5))
		"eddystone":
			root.add_child(lighthouse(42.0))
			GroundKit.cyl(root, 14.0, 20.0, 6.0, Vector3(0, 1.0, 0), Color(0.3, 0.3, 0.32), Vector3.ZERO, 8)
		"needles":
			for i in 3:
				_b(root, Vector3(10, 28.0 - float(i) * 6.0, 10), Vector3(float(i) * 22.0, 12.0 - float(i) * 2.0, float(i) * 6.0 - 4.0), Color(0.88, 0.88, 0.84), Vector3(0, 12.0 * float(i), 8))
			root.add_child(lighthouse(22.0))
			root.get_child(root.get_child_count() - 1).position = Vector3(70, 0, 8)
		"pegasus_bridge":
			_b(root, Vector3(40, 2.0, 7.0), Vector3(0, 4.0, 0), Color(0.3, 0.32, 0.36))
			for sz in [-1.0, 1.0]:
				_b(root, Vector3(40, 0.9, 0.9), Vector3(0, 9.0, sz * 3.2), Color(0.3, 0.32, 0.36))
				for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
					_b(root, Vector3(0.7, 6.0, 0.7), Vector3(x, 6.5, sz * 3.2), Color(0.3, 0.32, 0.36))
			for sx in [-1.0, 1.0]:
				_b(root, Vector3(6, 6, 9), Vector3(sx * 22.0, 2.5, 0), GroundKit.COL_CONCRETE)
		"arromanches_mulberry":
			# line of concrete caissons and a floating roadway
			for i in 8:
				_b(root, Vector3(16, 7, 40), Vector3(float(i) * 44.0 - 150.0, 2.0, 0), Color(0.5, 0.5, 0.48))
			_b(root, Vector3(330, 1.0, 5), Vector3(0, 5.0, 40), Color(0.28, 0.28, 0.3))
			for i in 6:
				_b(root, Vector3(10, 3, 22), Vector3(float(i) * 55.0 - 140.0, 1.0, -34), Color(0.36, 0.38, 0.34), Vector3(0, 8.0 * float(i % 3), 0))
		"cologne_cathedral":
			_cathedral(root, 150.0, 46.0, 157.0, 2, 28.0, Color(0.34, 0.33, 0.32))
		"antwerp_cathedral":
			_cathedral(root, 120.0, 50.0, 123.0, 1, 18.0, Color(0.7, 0.67, 0.58))
		"bruges_belfry":
			_b(root, Vector3(20, 56, 20), Vector3(0, 28, 0), Color(0.62, 0.4, 0.32))
			_b(root, Vector3(24, 10, 24), Vector3(0, 61, 0), Color(0.68, 0.64, 0.56))
			GroundKit.cyl(root, 0.0, 9.0, 20.0, Vector3(0, 76, 0), dark, Vector3.ZERO, 8)
			_b(root, Vector3(70, 14, 28), Vector3(-45, 7, 0), Color(0.66, 0.58, 0.48))
		"utrecht_dom":
			_b(root, Vector3(16, 100, 16), Vector3(0, 50, 0), Color(0.62, 0.58, 0.5))
			_b(root, Vector3(18, 10, 18), Vector3(0, 105, 0), Color(0.68, 0.64, 0.56))
			GroundKit.cyl(root, 0.0, 6.0, 14.0, Vector3(0, 117, 0), dark, Vector3.ZERO, 8)
			_b(root, Vector3(40, 22, 90), Vector3(0, 11, 60), Color(0.64, 0.6, 0.52))
		"aachen_cathedral":
			_cathedral(root, 100.0, 34.0, 60.0, 1, 14.0, Color(0.66, 0.62, 0.54), true)
		"frankfurt_cathedral":
			_cathedral(root, 100.0, 36.0, 95.0, 1, 18.0, Color(0.62, 0.34, 0.28))
		"coventry_cathedral":
			_cathedral(root, 100.0, 30.0, 90.0, 1, 30.0, Color(0.5, 0.46, 0.4), false, true)
		"canterbury_cathedral":
			_cathedral(root, 140.0, 38.0, 72.0, 2, 0.0, Color(0.72, 0.68, 0.58))
			_b(root, Vector3(18, 78, 18), Vector3(0, 39, 0), Color(0.72, 0.68, 0.58))
		"salisbury_cathedral":
			_cathedral(root, 120.0, 36.0, 40.0, 1, 0.0, Color(0.74, 0.72, 0.64))
			_b(root, Vector3(14, 50, 14), Vector3(0, 25, 0), Color(0.74, 0.72, 0.64))
			GroundKit.cyl(root, 0.0, 7.0, 70.0, Vector3(0, 85, 0), Color(0.62, 0.64, 0.66), Vector3.ZERO, 4)
		"rouen_cathedral":
			_cathedral(root, 130.0, 40.0, 72.0, 2, 14.0, Color(0.7, 0.66, 0.56))
			GroundKit.cyl(root, 0.0, 6.0, 90.0, Vector3(0, 105, -10), Color(0.34, 0.36, 0.4), Vector3.ZERO, 4)
		"amiens_cathedral":
			_cathedral(root, 140.0, 44.0, 66.0, 2, 0.0, Color(0.72, 0.68, 0.58))
		"caen_abbey":
			_cathedral(root, 90.0, 28.0, 80.0, 2, 24.0, Color(0.72, 0.7, 0.62))
		"bayeux_cathedral":
			_cathedral(root, 100.0, 30.0, 58.0, 2, 20.0, Color(0.7, 0.66, 0.58))
		"windsor_castle":
			_b(root, Vector3(120, 10, 80), Vector3(0, 5, 0), Color(0.7, 0.68, 0.6))
			GroundKit.cyl(root, 14.0, 16.0, 30.0, Vector3(0, 25, 0), stone, Vector3.ZERO, 12)
			GroundKit.cyl(root, 0.0, 12.0, 8.0, Vector3(0, 44, 0), dark, Vector3.ZERO, 12)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 4.0, 4.6, 22.0, Vector3(sx * 58.0, 16, sz * 38.0), stone, Vector3.ZERO, 8)
		"stonehenge":
			for k in 14:
				var a: float = TAU * float(k) / 14.0
				_b(root, Vector3(2.4, 7.0, 1.4), Vector3(cos(a) * 17.0, 3.5, sin(a) * 17.0), Color(0.58, 0.56, 0.52), Vector3(0, -rad_to_deg(a), 0))
				if k % 2 == 0:
					var b: float = a + TAU / 28.0
					_b(root, Vector3(9.0, 1.2, 1.6), Vector3(cos(b) * 17.0, 7.3, sin(b) * 17.0), Color(0.58, 0.56, 0.52), Vector3(0, -rad_to_deg(b) + 90.0, 0))
		"ludendorff_bridge":
			_arch_bridge(root, 240.0, 24.0, Color(0.34, 0.36, 0.4), true, EraClock.current() >= "1945-03-17")   # collapsed 17 Mar 1945
		"nijmegen_bridge":
			_arch_bridge(root, 300.0, 40.0, Color(0.32, 0.34, 0.38), false)
		"arnhem_bridge":
			_arch_bridge(root, 200.0, 22.0, Color(0.38, 0.4, 0.42), false, EraClock.current() >= "1944-10-07")   # bombed down 7 Oct 1944
		"battersea_power_station":
			_b(root, Vector3(120, 34, 70), Vector3(0, 17, 0), Color(0.55, 0.33, 0.26))
			_b(root, Vector3(90, 30, 60), Vector3(105, 15, 0), Color(0.48, 0.3, 0.24))
			for sz in [-1.0, 1.0]:
				GroundKit.cyl(root, 7.0, 10.0, 100.0, Vector3(-40.0, 50.0, sz * 22.0), Color(0.5, 0.32, 0.26), Vector3.ZERO, 10)
				GroundKit.cyl(root, 6.5, 8.5, 8.0, Vector3(-40.0, 104.0, sz * 22.0), Color(0.44, 0.3, 0.26), Vector3.ZERO, 10)
		"tower_of_london":
			_b(root, Vector3(90, 4, 80), Vector3(0, 2, 0), Color(0.7, 0.68, 0.6))
			for k in 12:
				var a: float = TAU * float(k) / 12.0
				GroundKit.cyl(root, 3.5, 4.0, 14.0, Vector3(cos(a) * 42.0, 7.0, sin(a) * 38.0), stone, Vector3.ZERO, 8)
			_b(root, Vector3(30, 30, 30), Vector3(0, 19, 0), Color(0.86, 0.84, 0.78))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 6.0, 6.0, 36.0, Vector3(sx * 15.0, 22.0, sz * 15.0), Color(0.9, 0.88, 0.82), Vector3.ZERO, 8)
					GroundKit.sphere(root, 7.0, Vector3(sx * 15.0, 40.0, sz * 15.0), Color(0.9, 0.88, 0.82), Vector3(1.0, 0.7, 1.0))
		"westminster_abbey":
			_cathedral(root, 110.0, 34.0, 69.0, 2, 0.0, Color(0.72, 0.68, 0.58))
			_b(root, Vector3(16, 60, 16), Vector3(0, 30, 0), Color(0.7, 0.66, 0.56))
			GroundKit.cyl(root, 0.0, 6.0, 16.0, Vector3(0, 68, 0), dark, Vector3.ZERO, 4)
		"royal_albert_hall":
			var drum := GroundKit.cyl(root, 52.0, 54.0, 30.0, Vector3(0, 15, 0), Color(0.62, 0.32, 0.24), Vector3.ZERO, 20)
			drum.scale = Vector3(1.0, 1.0, 0.78)
			GroundKit.sphere(root, 50.0, Vector3(0, 30.0, 0), Color(0.5, 0.52, 0.52), Vector3(1.0, 0.4, 0.78))
			for k in 16:
				var a: float = TAU * float(k) / 16.0
				_b(root, Vector3(5, 42, 5), Vector3(cos(a) * 54.0, 21.0, sin(a) * 42.0), Color(0.58, 0.3, 0.22), Vector3(0, -rad_to_deg(a), 0))
		"crystal_palace":
			for sx in [-1.0, 1.0]:
				_b(root, Vector3(16, 30, 16), Vector3(sx * 40.0, 15, 0), Color(0.66, 0.62, 0.52))
				GroundKit.cyl(root, 0.0, 14.0, 26.0, Vector3(sx * 40.0, 43.0, 0), Color(0.6, 0.56, 0.48), Vector3.ZERO, 10)
				GroundKit.cyl(root, 0.0, 4.0, 18.0, Vector3(sx * 40.0, 65.0, 0), Color(0.34, 0.36, 0.4), Vector3.ZERO, 8)
			_b(root, Vector3(200, 4, 60), Vector3(0, 2, 0), Color(0.7, 0.68, 0.58))
		"wembley_stadium":
			for k in 22:
				var a: float = TAU * float(k) / 22.0
				_b(root, Vector3(24, 14, 24), Vector3(cos(a) * 70.0, 7, sin(a) * 52.0), Color(0.62, 0.6, 0.54), Vector3(0, -rad_to_deg(a), 0))
			_b(root, Vector3(60, 3, 40), Vector3(0, 2, 0), Color(0.4, 0.5, 0.32))
			for sx in [-1.0, 1.0]:
				_b(root, Vector3(14, 40, 14), Vector3(sx * 20.0, 20, 52.0), Color(0.9, 0.9, 0.88))
			GroundKit.cyl(root, 0.0, 5.0, 12.0, Vector3(20.0, 46, 52.0), dark, Vector3.ZERO, 4)
		"london_docks":
			for r in 5:
				for c in 4:
					_b(root, Vector3(16, 12, 40), Vector3(float(c) * 34.0 - 51.0, 6, float(r) * 70.0 - 140.0), Color(0.5, 0.3, 0.24))
			for r in 4:
				GroundKit.cyl(root, 22.0, 24.0, 20.0, Vector3(90.0, 10, float(r) * 80.0 - 120.0), Color(0.42, 0.44, 0.46), Vector3.ZERO, 12)
		"county_hall":
			_b(root, Vector3(180, 26, 50), Vector3(0, 13, 0), Color(0.78, 0.75, 0.66))
			for i in 12:
				GroundKit.cyl(root, 3.0, 3.0, 22.0, Vector3(-70.0 + float(i) * 13.0, 12, -26.0), Color(0.82, 0.8, 0.72), Vector3.ZERO, 8)
			GroundKit.cyl(root, 20.0, 22.0, 20.0, Vector3(0, 36, 0), Color(0.74, 0.72, 0.64), Vector3.ZERO, 12)
			GroundKit.sphere(root, 22.0, Vector3(0, 46, 0), Color(0.5, 0.58, 0.56), Vector3(1.0, 0.7, 1.0))
		"the_monument":
			_b(root, Vector3(16, 8, 16), Vector3(0, 4, 0), stone)
			GroundKit.cyl(root, 4.0, 5.0, 62.0, Vector3(0, 39, 0), Color(0.72, 0.68, 0.58), Vector3.ZERO, 12)
			GroundKit.cyl(root, 0.0, 5.5, 6.0, Vector3(0, 73, 0), Color(0.5, 0.4, 0.2), Vector3.ZERO, 12)
			GroundKit.sphere(root, 4.0, Vector3(0, 78, 0), Color(0.85, 0.65, 0.2))
		"rochester_castle":
			_b(root, Vector3(40, 14, 40), Vector3(0, 7, 0), Color(0.6, 0.58, 0.5))
			_b(root, Vector3(26, 48, 26), Vector3(0, 38, 0), stone)
			_b(root, Vector3(28, 4, 28), Vector3(0, 64, 0), Color(0.58, 0.55, 0.48))
			var rroof := MeshInstance3D.new()
			rroof.mesh = GroundKit.prism_mesh(30.0, 30.0, 10.0)
			rroof.material_override = GroundKit.mat(dark, true)
			rroof.position = Vector3(0, 66, 0)
			root.add_child(rroof)
		"rochester_cathedral":
			_cathedral(root, 100.0, 32.0, 50.0, 1, 0.0, Color(0.68, 0.64, 0.56))
			_b(root, Vector3(16, 56, 16), Vector3(0, 28, 0), Color(0.66, 0.62, 0.54))
		"leeds_castle":
			_b(root, Vector3(70, 2, 60), Vector3(0, 1, 0), Color(0.3, 0.5, 0.6))
			_b(root, Vector3(40, 4, 34), Vector3(0, 5, 0), Color(0.66, 0.62, 0.54))
			_b(root, Vector3(18, 22, 18), Vector3(0, 16, 0), stone)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 4.0, 4.5, 24.0, Vector3(sx * 18.0, 19.0, sz * 15.0), stone, Vector3.ZERO, 8)
					GroundKit.cyl(root, 0.0, 5.0, 6.0, Vector3(sx * 18.0, 34.0, sz * 15.0), dark, Vector3.ZERO, 8)
		"dover_great_tower":
			_b(root, Vector3(60, 16, 50), Vector3(0, 8, 0), Color(0.6, 0.58, 0.5))
			_b(root, Vector3(30, 40, 30), Vector3(0, 36, 0), stone)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 4.0, 4.0, 44.0, Vector3(sx * 15.0, 36.0, sz * 15.0), stone, Vector3.ZERO, 8)
			GroundKit.cyl(root, 5.0, 6.0, 26.0, Vector3(26.0, 21.0, 8.0), Color(0.64, 0.6, 0.52), Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.0, 6.0, 6.0, Vector3(26.0, 37.0, 8.0), dark, Vector3.ZERO, 8)
		"dover_admiralty_pier":
			_b(root, Vector3(1000, 6, 26), Vector3(0, 3, 0), Color(0.6, 0.58, 0.52))
			GroundKit.cyl(root, 20.0, 20.0, 8.0, Vector3(500.0, 4.0, 0), Color(0.58, 0.56, 0.5), Vector3.ZERO, 12)
			_b(root, Vector3(14, 24, 14), Vector3(-490.0, 12, 0), Color(0.62, 0.58, 0.5))
		"hever_castle":
			_b(root, Vector3(60, 2, 60), Vector3(0, 1, 0), Color(0.3, 0.5, 0.6))
			_b(root, Vector3(30, 4, 26), Vector3(0, 5, 0), Color(0.64, 0.6, 0.52))
			_b(root, Vector3(16, 18, 14), Vector3(0, 14, 0), Color(0.66, 0.5, 0.42))
			GroundKit.cyl(root, 3.0, 3.2, 20.0, Vector3(0, 16, 8.0), Color(0.64, 0.58, 0.5), Vector3.ZERO, 8)
			for sx in [-1.0, 1.0]:
				GroundKit.cyl(root, 2.5, 2.8, 16.0, Vector3(sx * 10.0, 12.0, 6.0), Color(0.64, 0.58, 0.5), Vector3.ZERO, 8)
		"new_romney_st_nicholas":
			root.add_child(church(1.35))
			_b(root, Vector3(14, 34, 14), Vector3(0, 17, 22.0), Color(0.66, 0.62, 0.54))
		"rye_st_mary":
			root.add_child(church(1.2))
			GroundKit.cyl(root, 1.4, 1.4, 3.0, Vector3(0, 15.5, 15.5), Color(0.85, 0.7, 0.3), Vector3(90, 0, 0), 10)
		"sandwich_st_clements":
			root.add_child(church(1.15))
		"chatham_dockyard":
			for r in 3:
				for c in 5:
					_b(root, Vector3(50, 20, 26), Vector3(float(c) * 60.0 - 120.0, 10, float(r) * 60.0 - 60.0), Color(0.42, 0.44, 0.46))
			for c in 5:
				_b(root, Vector3(70, 6, 20), Vector3(float(c) * 70.0 - 140.0, 3, 90.0), Color(0.5, 0.5, 0.48))
			for c in 6:
				GroundKit.cyl(root, 0.0, 2.5, 40.0, Vector3(float(c) * 46.0 - 115.0, 20, 60.0), dark, Vector3.ZERO, 6)
		"ramsgate_harbour":
			_b(root, Vector3(12, 12, 240), Vector3(90.0, 6, 0), Color(0.6, 0.58, 0.52))
			_b(root, Vector3(240, 12, 12), Vector3(0, 6, 120.0), Color(0.6, 0.58, 0.52))
			var rlh := lighthouse(32.0)
			root.add_child(rlh)
			rlh.position = Vector3(90.0, 0, -120.0)
		"dunkerque_belfry":
			_b(root, Vector3(14, 52, 14), Vector3(0, 26, 0), Color(0.55, 0.3, 0.24))
			_b(root, Vector3(18, 12, 18), Vector3(0, 58, 0), Color(0.6, 0.56, 0.5))
			GroundKit.cyl(root, 6.0, 7.0, 10.0, Vector3(0, 69, 0), dark, Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.0, 5.0, 6.0, Vector3(0, 77, 0), dark, Vector3.ZERO, 8)
			_b(root, Vector3(40, 18, 22), Vector3(-34.0, 9, 0), Color(0.62, 0.58, 0.5))
		"boulogne_basilica":
			_cathedral(root, 100.0, 36.0, 44.0, 2, 0.0, Color(0.7, 0.66, 0.56))
			GroundKit.cyl(root, 22.0, 24.0, 30.0, Vector3(0, 44.0, 0), Color(0.68, 0.64, 0.54), Vector3.ZERO, 16)
			GroundKit.sphere(root, 26.0, Vector3(0, 62.0, 0), Color(0.52, 0.6, 0.58), Vector3(1.0, 0.8, 1.0))
		"boulogne_column":
			_b(root, Vector3(24, 6, 24), Vector3(0, 3, 0), stone)
			_b(root, Vector3(18, 6, 18), Vector3(0, 9, 0), stone)
			GroundKit.cyl(root, 4.0, 5.0, 48.0, Vector3(0, 36, 0), Color(0.72, 0.68, 0.58), Vector3.ZERO, 12)
			_b(root, Vector3(8, 10, 8), Vector3(0, 65, 0), Color(0.35, 0.3, 0.22))
		"lille_hotel_de_ville":
			_b(root, Vector3(120, 26, 46), Vector3(-40.0, 13, 0), Color(0.6, 0.34, 0.26))
			_b(root, Vector3(30, 34, 30), Vector3(60.0, 17, 0), Color(0.58, 0.34, 0.26))
			_b(root, Vector3(20, 60, 20), Vector3(60.0, 64, 0), Color(0.6, 0.36, 0.28))
			_b(root, Vector3(24, 10, 24), Vector3(60.0, 99, 0), Color(0.66, 0.62, 0.54))
			GroundKit.cyl(root, 0.0, 9.0, 12.0, Vector3(60.0, 110, 0), dark, Vector3.ZERO, 4)
		"lille_citadel":
			for k in 5:
				var a: float = TAU * float(k) / 5.0
				_b(root, Vector3(50, 10, 16), Vector3(cos(a) * 55.0, 5, sin(a) * 55.0), Color(0.6, 0.56, 0.5), Vector3(0, -rad_to_deg(a), 0))
			GroundKit.cyl(root, 60.0, 62.0, 8.0, Vector3(0, 4, 0), Color(0.6, 0.56, 0.5), Vector3.ZERO, 10)
			_b(root, Vector3(34, 22, 34), Vector3(0, 15, 0), Color(0.62, 0.58, 0.52))
		"ghent_belfry":
			_b(root, Vector3(18, 80, 18), Vector3(0, 40, 0), Color(0.72, 0.68, 0.58))
			_b(root, Vector3(22, 8, 22), Vector3(0, 84, 0), Color(0.74, 0.7, 0.6))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 2.0, 2.4, 20.0, Vector3(sx * 10.0, 88.0, sz * 10.0), Color(0.68, 0.64, 0.54), Vector3.ZERO, 8)
			GroundKit.cyl(root, 0.0, 6.0, 12.0, Vector3(0, 94, 0), dark, Vector3.ZERO, 8)
		"ghent_gravensteen":
			_b(root, Vector3(44, 30, 34), Vector3(0, 15, 0), Color(0.62, 0.6, 0.54))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 6.0, 7.0, 34.0, Vector3(sx * 22.0, 17.0, sz * 17.0), stone, Vector3.ZERO, 8)
			_b(root, Vector3(70, 2, 60), Vector3(0, 1, 0), Color(0.3, 0.5, 0.6))
		"brussels_palais_de_justice":
			_b(root, Vector3(160, 30, 120), Vector3(0, 15, 0), Color(0.66, 0.62, 0.54))
			for i in 10:
				GroundKit.cyl(root, 4.0, 4.0, 24.0, Vector3(-80.0 + float(i) * 18.0, 12, -62.0), Color(0.7, 0.66, 0.58), Vector3.ZERO, 8)
			GroundKit.cyl(root, 26.0, 28.0, 30.0, Vector3(0, 45.0, 0), Color(0.64, 0.6, 0.52), Vector3.ZERO, 16)
			GroundKit.sphere(root, 30.0, Vector3(0, 66.0, 0), Color(0.5, 0.56, 0.55), Vector3(1.0, 0.85, 1.0))
		"brussels_hotel_de_ville":
			_b(root, Vector3(60, 22, 30), Vector3(-30.0, 11, 0), Color(0.66, 0.6, 0.5))
			_b(root, Vector3(22, 30, 22), Vector3(30.0, 15, 0), Color(0.64, 0.58, 0.48))
			_b(root, Vector3(16, 70, 16), Vector3(30.0, 65, 0), Color(0.7, 0.64, 0.54))
			_b(root, Vector3(20, 10, 20), Vector3(30.0, 103, 0), Color(0.72, 0.66, 0.56))
			GroundKit.cyl(root, 0.0, 7.0, 26.0, Vector3(30.0, 121, 0), dark, Vector3.ZERO, 4)
		"antwerp_docks":
			for r in 4:
				for c in 4:
					_b(root, Vector3(20, 16, 90), Vector3(float(c) * 50.0 - 75.0, 8, float(r) * 120.0 - 180.0), Color(0.6, 0.58, 0.5))
			for c in 3:
				GroundKit.cyl(root, 14.0, 16.0, 40.0, Vector3(120.0, 20, float(c) * 100.0 - 100.0), Color(0.5, 0.5, 0.46), Vector3.ZERO, 12)
			for c in 6:
				GroundKit.cyl(root, 0.0, 2.0, 46.0, Vector3(float(c) * 40.0 - 100.0, 23, 200.0), dark, Vector3.ZERO, 6)
		"zeebrugge_mole":
			_b(root, Vector3(2500, 8, 30), Vector3(0, 4, 0), Color(0.58, 0.56, 0.5))
			GroundKit.cyl(root, 16.0, 16.0, 10.0, Vector3(1200.0, 5, 0), Color(0.56, 0.54, 0.48), Vector3.ZERO, 12)
			var zlh := lighthouse(40.0)
			root.add_child(zlh)
			zlh.position = Vector3(1150.0, 0, 0)
		"rotterdam_maashaven":
			for r in 4:
				for c in 5:
					_b(root, Vector3(40, 12, 40), Vector3(float(c) * 70.0 - 140.0, 6, float(r) * 90.0 - 135.0), Color(0.42, 0.44, 0.46))
			for c in 4:
				GroundKit.cyl(root, 16.0, 18.0, 44.0, Vector3(180.0, 22, float(c) * 100.0 - 150.0), Color(0.5, 0.5, 0.46), Vector3.ZERO, 12)
			for c in 5:
				_b(root, Vector3(30, 10, 90), Vector3(float(c) * 80.0 - 160.0, 5, 220.0), Color(0.46, 0.46, 0.44))
		"ostend_harbour":
			_b(root, Vector3(12, 10, 160), Vector3(60.0, 5, 0), Color(0.6, 0.58, 0.52))
			_b(root, Vector3(12, 10, 160), Vector3(-60.0, 5, 0), Color(0.6, 0.58, 0.52))
			_b(root, Vector3(34, 26, 180), Vector3(130.0, 13, 0), Color(0.66, 0.6, 0.5))
			var olh := lighthouse(28.0)
			root.add_child(olh)
			olh.position = Vector3(60.0, 0, -80.0)
		"cologne_hohenzollern_bridge":
			_arch_bridge(root, 260.0, 26.0, Color(0.34, 0.36, 0.4), false)
		"cologne_gross_st_martin":
			root.add_child(church(1.5))
			_b(root, Vector3(18, 40, 18), Vector3(0, 20, 0), Color(0.68, 0.64, 0.54))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					GroundKit.cyl(root, 3.0, 3.4, 34.0, Vector3(sx * 9.0, 37.0, sz * 9.0), Color(0.68, 0.64, 0.54), Vector3.ZERO, 8)
					GroundKit.cyl(root, 0.0, 4.0, 10.0, Vector3(sx * 9.0, 59.0, sz * 9.0), dark, Vector3.ZERO, 8)
		"koblenz_deutsches_eck":
			_b(root, Vector3(40, 8, 40), Vector3(0, 4, 0), stone)
			_b(root, Vector3(30, 10, 30), Vector3(0, 13, 0), stone)
			_b(root, Vector3(18, 24, 18), Vector3(0, 30, 0), Color(0.64, 0.6, 0.52))
			GroundKit.cyl(root, 4.0, 5.0, 30.0, Vector3(0, 57, 0), Color(0.4, 0.36, 0.3), Vector3.ZERO, 12)
			_b(root, Vector3(6, 14, 6), Vector3(0, 78, 0), Color(0.32, 0.28, 0.22))
		"liege_palais_des_princes_eveques":
			_b(root, Vector3(150, 26, 34), Vector3(0, 13, -40.0), Color(0.62, 0.58, 0.5))
			_b(root, Vector3(150, 26, 34), Vector3(0, 13, 40.0), Color(0.62, 0.58, 0.5))
			for i in 10:
				GroundKit.cyl(root, 2.0, 2.0, 22.0, Vector3(-68.0 + float(i) * 15.0, 11, -60.0), Color(0.66, 0.62, 0.54), Vector3.ZERO, 8)
			_b(root, Vector3(26, 34, 26), Vector3(0, 17, 0), Color(0.6, 0.56, 0.48))
		"birmingham_town_hall":
			_b(root, Vector3(80, 26, 50), Vector3(0, 15, 0), Color(0.72, 0.7, 0.62))
			_b(root, Vector3(90, 6, 56), Vector3(0, 3, 0), stone)
			for i in 8:
				GroundKit.cyl(root, 3.0, 3.0, 24.0, Vector3(-49.0 + float(i) * 14.0, 15, -26.0), Color(0.76, 0.74, 0.66), Vector3.ZERO, 8)
			var ped := MeshInstance3D.new()
			ped.mesh = GroundKit.prism_mesh(56.0, 14.0, 12.0)
			ped.material_override = GroundKit.mat(Color(0.72, 0.7, 0.62), true)
			ped.position = Vector3(0, 28, -26.0)
			root.add_child(ped)
		"birmingham_council_house":
			_b(root, Vector3(120, 26, 44), Vector3(0, 13, 0), Color(0.7, 0.66, 0.58))
			_b(root, Vector3(30, 34, 30), Vector3(0, 17, 0), Color(0.72, 0.68, 0.6))
			GroundKit.sphere(root, 14.0, Vector3(0, 36, 0), Color(0.5, 0.58, 0.56), Vector3(1.0, 0.8, 1.0))
			GroundKit.cyl(root, 0.0, 1.5, 30.0, Vector3(0, 56, 0), dark, Vector3.ZERO, 6)
		"coventry_holy_trinity_spire":
			_b(root, Vector3(20, 12, 44), Vector3(0, 6, 0), stone)
			var croof := MeshInstance3D.new()
			croof.mesh = GroundKit.prism_mesh(22.0, 46.0, 5.0)
			croof.material_override = GroundKit.mat(dark, true)
			croof.position = Vector3(0, 12, 0)
			root.add_child(croof)
			_b(root, Vector3(12, 34, 12), Vector3(0, 29, 20.0), stone)
			GroundKit.cyl(root, 0.0, 7.0, 38.0, Vector3(0, 65, 20.0), Color(0.6, 0.62, 0.66), Vector3.ZERO, 4)
		"coventry_council_house":
			_b(root, Vector3(110, 24, 40), Vector3(0, 12, 0), Color(0.7, 0.66, 0.58))
			for i in 6:
				GroundKit.cyl(root, 2.5, 2.5, 22.0, Vector3(-20.0 + float(i) * 8.0, 11, -22.0), Color(0.74, 0.7, 0.62), Vector3.ZERO, 8)
			_b(root, Vector3(16, 40, 16), Vector3(45.0, 20, 0), Color(0.68, 0.64, 0.56))
			GroundKit.cyl(root, 0.0, 5.0, 10.0, Vector3(45.0, 44, 0), dark, Vector3.ZERO, 4)
		"nottingham_council_house":
			_b(root, Vector3(90, 26, 50), Vector3(0, 13, 0), Color(0.72, 0.7, 0.62))
			for i in 8:
				GroundKit.cyl(root, 3.0, 3.0, 26.0, Vector3(-49.0 + float(i) * 14.0, 16, -26.0), Color(0.76, 0.74, 0.66), Vector3.ZERO, 8)
			GroundKit.cyl(root, 20.0, 22.0, 20.0, Vector3(0, 36, 0), Color(0.7, 0.68, 0.6), Vector3.ZERO, 14)
			GroundKit.sphere(root, 24.0, Vector3(0, 52, 0), Color(0.5, 0.58, 0.56), Vector3(1.0, 0.85, 1.0))
		"martello_tower":
			_martello(root)
		"coastguard_station":
			_coastguard_station(root)
		"lifeboat_station":
			_lifeboat_station(root)
		"lido":
			_lido(root)
		"bandstand":
			_bandstand(root)
		"holiday_camp":
			_holiday_camp(root)
		_:
			root.free()
			return null
	root.scale = Vector3.ONE * 1.0
	return root
