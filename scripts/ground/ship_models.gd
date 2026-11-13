class_name ShipModels
extends RefCounted
## Detailed ship models for GroundShip (realistic scenery): a lofted hull with sheer, flared bow, a coloured boot-top
## and a planked deck, plus the superstructure, funnels, guns, masts, derricks and boats of each type. Each model is
## ONE mesh with vertex colours on a matte painted material, so a ship is a single draw. Axes: bow -Z, stern +Z, up +Y,
## the waterline at y = 0. Geometry is original; nothing is taken from any other game.

static var _cache: Dictionary = {}
static var _mat: ShaderMaterial

const DECK := Color(0.30, 0.26, 0.20)
const DARK := Color(0.12, 0.12, 0.13)
const RED := Color(0.36, 0.14, 0.11)
const WHITE := Color(0.80, 0.78, 0.70)


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = (TownModels.paint_material() as ShaderMaterial).duplicate()
		_mat.set_shader_parameter("wear", 0.22)
		_mat.set_shader_parameter("roughness_v", 0.72)
	return _mat


## The model for a ship type. Cached per type + team (the team only changes the paint).
static func build(stype: String, allies: bool, length: float, beam: float) -> ArrayMesh:
	var key: String = "%s_%s" % [stype, str(allies)]
	if _cache.has(key):
		return _cache[key]
	var b := TownModels.MB.new()
	var grey: Color = Color(0.45, 0.5, 0.55) if allies else Color(0.38, 0.4, 0.42)
	match stype:
		"destroyer":
			_hull(b, length, beam, 2.0, 2.0, 0.08, grey, grey.darkened(0.1))
			_destroyer(b, length, beam, grey)
		"freighter":
			var hc: Color = Color(0.28, 0.24, 0.20) if allies else Color(0.18, 0.20, 0.22)
			_hull(b, length, beam, 3.0, 2.6, 0.10, hc, hc.lightened(0.1))
			_freighter(b, length, beam, hc, false, allies)
		"collier":
			var hc2: Color = Color(0.24, 0.22, 0.20) if allies else Color(0.20, 0.20, 0.21)
			_hull(b, length, beam, 3.6, 3.0, 0.12, hc2, hc2.lightened(0.08))
			_freighter(b, length, beam, hc2, true, allies)
		"trawler":
			var tc: Color = Color(0.42, 0.46, 0.50) if allies else Color(0.36, 0.38, 0.40)
			_hull(b, length, beam, 1.8, 1.8, 0.14, tc, tc.lightened(0.05))
			_trawler(b, length, beam, tc)
		"cruiser", "battleship":
			var big: bool = stype == "battleship"
			_hull(b, length, beam, 2.6 if big else 2.2, 2.4, 0.07, grey, grey.darkened(0.1))
			_capital(b, length, beam, grey, big)
		"ferry":
			_hull(b, length, beam, 2.4, 2.4, 0.12, Color(0.16, 0.17, 0.20), Color(0.22, 0.22, 0.25))
			_ferry(b, length, beam)
		"landing_craft":
			_hull(b, length, beam, 0.9, 1.4, 0.35, Color(0.34, 0.37, 0.30), Color(0.30, 0.32, 0.26))
			_landing_craft(b, length, beam)
		_:
			_hull(b, length, beam, 1.0, 1.1, 0.12, Color(0.30, 0.32, 0.38) if allies else Color(0.22, 0.25, 0.30), DECK)
			_fishing_boat(b, length, beam)
	var m: ArrayMesh = b.commit(material())
	_cache[key] = m
	return m


# ---------------------------------------------------------------- hull

static func _hull(b: TownModels.MB, length: float, beam: float, depth: float, fb: float, bow_sharp: float, hull_c: Color, deck_c: Color) -> void:
	var n: int = 16
	var rings: Array = []
	for i in n + 1:
		var t: float = float(i) / float(n)                    # 0 = bow (-Z), 1 = stern
		var wfac: float
		if t < 0.3:
			wfac = lerpf(bow_sharp, 1.0, sin(t / 0.3 * PI * 0.5))
		elif t > 0.88:
			wfac = lerpf(1.0, 0.72, (t - 0.88) / 0.12)
		else:
			wfac = 1.0
		var w: float = beam * 0.5 * wfac
		# a flared bow carries the deck line out wider than the waterline
		var flare: float = 1.0 + 0.10 * pow(maxf(1.0 - t / 0.35, 0.0), 1.5)
		var top: float = fb * (1.0 + 0.5 * pow(1.0 - t, 3.0) + 0.12 * pow(t, 4.0))
		var z: float = -length * 0.5 + length * t
		rings.append([
			Vector3(-w * flare, top, z), Vector3(w * flare, top, z), Vector3(w * 0.97, 0.0, z),
			Vector3(w * 0.62, -depth * 0.92, z), Vector3(-w * 0.62, -depth * 0.92, z), Vector3(-w * 0.97, 0.0, z),
			Vector3(-w * 0.97, 0.0, z), Vector3(-w * 0.62, -depth * 0.92, z)])
	for i in n:
		var a: Array = rings[i]
		var c: Array = rings[i + 1]
		# deck
		b.face([a[0], a[1], c[1], c[0]], deck_c, Vector3.UP)
		# starboard side: above the waterline in the hull colour, a red boot-top band below it
		b.face([a[1], a[2], c[2], c[1]], hull_c, Vector3.RIGHT)
		b.face([a[2], a[3], c[3], c[2]], RED, Vector3(1, -1, 0))
		b.face([a[0], a[5], c[5], c[0]], hull_c, Vector3.LEFT)
		b.face([a[5], a[4], c[4], c[5]], RED, Vector3(-1, -1, 0))
		b.face([a[3], a[4], c[4], c[3]], RED, Vector3.DOWN)
	# bow and transom
	var r0: Array = rings[0]
	var r1: Array = rings[n]
	b.face([r0[0], r0[1], r0[2], r0[3], r0[4], r0[5]], hull_c, Vector3.FORWARD)
	b.face([r1[0], r1[1], r1[2], r1[3], r1[4], r1[5]], hull_c.darkened(0.1), Vector3.BACK)
	# a low bulwark along each side of the deck, and the forecastle break
	var bw: float = beam * 0.5
	for sx in [-1.0, 1.0]:
		b.box(sx * (bw * 0.93) - 0.07, sx * (bw * 0.93) + 0.07, fb, fb + 0.5, -length * 0.40, length * 0.46, hull_c.lightened(0.04), true, deck_c.lightened(0.1))
	b.box(-bw * 0.93, bw * 0.93, fb, fb + 0.7, -length * 0.5 + 1.0, -length * 0.5 + 1.25, hull_c)


# ---------------------------------------------------------------- fittings

## Raked oval funnel with a dark cap and a thin steam pipe.
static func _funnel(b: TownModels.MB, x: float, y: float, z: float, h: float, rx: float, rz: float, col: Color, cap: Color = Color(0.10, 0.10, 0.11)) -> void:
	b.prism(x, z, y, y + h, rx, rz, rx * 0.88, rz * 0.82, 10, col, false)
	b.prism(x, z, y + h, y + h + 0.35, rx * 0.9, rz * 0.84, rx * 0.9, rz * 0.84, 10, cap, true)
	b.box(x - 0.06, x + 0.06, y, y + h * 0.9, z + rz * 0.95, z + rz * 1.25, DARK, false)


## Gun mount: a round barbette and a shielded house with barrels pointing forward (-Z).
static func _turret(b: TownModels.MB, x: float, y: float, z: float, r: float, barrels: int, blen: float, col: Color, dir: float = 1.0) -> void:
	b.prism(x, z, y, y + r * 0.45, r, r, r, r, 10, col.darkened(0.12), true)
	b.prism(x, z, y + r * 0.45, y + r * 1.05, r * 0.95, r * 1.0, r * 0.78, r * 0.86, 8, col, true)
	for i in barrels:
		var bx: float = x + (float(i) - float(barrels - 1) * 0.5) * (r * 0.62)
		b.box(bx - 0.09, bx + 0.09, y + r * 0.62, y + r * 0.62 + 0.18, z - dir * (r * 0.6 + blen), z - dir * r * 0.5, DARK, true)


## Thin mast with a yard and a stay (a long thin box).
static func _mast(b: TownModels.MB, x: float, y: float, z: float, h: float, col: Color = Color(0.20, 0.20, 0.21)) -> void:
	b.box(x - 0.09, x + 0.09, y, y + h, z - 0.09, z + 0.09, col, true)
	b.box(x - h * 0.16, x + h * 0.16, y + h * 0.72, y + h * 0.72 + 0.12, z - 0.07, z + 0.07, col, true)


## Lifeboat on its davits.
static func _boat(b: TownModels.MB, x: float, y: float, z: float, l: float, col: Color) -> void:
	b.box(x - 0.55, x + 0.55, y, y + 0.55, z - l * 0.5, z + l * 0.5, col, true, col.lightened(0.15))
	b.box(x - 0.14, x + 0.14, y + 0.55, y + 0.75, z - l * 0.3, z + l * 0.3, col.darkened(0.2), true)
	for dz in [-0.28, 0.28]:
		b.box(x - 0.07, x + 0.07, y - 0.4, y + 1.2, z + dz * l - 0.07, z + dz * l + 0.07, DARK, false)


# ---------------------------------------------------------------- types

static func _destroyer(b: TownModels.MB, length: float, beam: float, grey: Color) -> void:
	var bow: float = -length * 0.5
	var deck: float = 2.0
	var light: Color = grey.lightened(0.10)
	# raised forecastle forward and a 'B' gun superfiring over 'A'
	b.box(-beam * 0.42, beam * 0.42, deck, deck + 0.7, bow + 1.0, bow + 8.0, grey, true, DECK)
	_turret(b, 0.0, deck + 0.7, bow + 4.5, 1.15, 2, 3.0, grey)
	_turret(b, 0.0, deck + 1.0, bow + 9.4, 1.15, 2, 3.0, grey)
	# bridge: two tiers with wing platforms, compass platform and a director on the roof
	var bz: float = bow + 13.5
	b.box(-1.5, 1.5, deck, deck + 2.6, bz - 2.0, bz + 2.0, light, true, grey.darkened(0.1))
	b.box(-1.2, 1.2, deck + 2.6, deck + 4.1, bz - 1.5, bz + 1.4, light.lightened(0.04), true, grey.darkened(0.12))
	b.box(-2.2, 2.2, deck + 2.6, deck + 2.85, bz - 1.2, bz + 0.8, grey.darkened(0.18), true)
	b.box(-0.8, 0.8, deck + 4.1, deck + 4.9, bz - 0.9, bz + 0.2, grey, true)
	b.box(-0.5, 0.5, deck + 4.9, deck + 5.6, bz - 0.6, bz + 0.0, DARK, true)
	# tripod mast behind the bridge, with a yard and the wireless aerial
	_mast(b, 0.0, deck + 4.1, bz + 2.6, 7.4, grey.darkened(0.3))
	# two funnels, the second slightly taller, raked aft
	_funnel(b, 0.0, deck, bz + 6.5, 4.4, 1.0, 1.5, grey.darkened(0.30))
	_funnel(b, 0.0, deck, bz + 11.2, 4.0, 0.95, 1.4, grey.darkened(0.30))
	# quad torpedo tubes, a pom-pom aft, 'X' and 'Y' guns and depth-charge rails
	b.box(-0.9, 0.9, deck, deck + 0.6, bz + 14.0, bz + 15.4, grey.darkened(0.2), true)
	for tx in [-0.4, 0.4]:
		b.box(tx - 0.2, tx + 0.2, deck + 0.6, deck + 1.0, bz + 13.7, bz + 15.7, DARK, true)
	_turret(b, 0.0, deck + 0.6, bz + 18.2, 1.05, 2, 2.6, grey, -1.0)
	b.box(-0.8, 0.8, deck, deck + 0.45, length * 0.5 - 2.2, length * 0.5 - 0.6, DARK, true)
	for rx in [-0.55, 0.55]:
		b.box(rx - 0.18, rx + 0.18, deck + 0.0, deck + 0.4, length * 0.5 - 1.0, length * 0.5 + 0.7, DARK, true)
	_boat(b, -1.35, deck + 0.1, bz + 8.0, 4.4, grey.darkened(0.25))
	_boat(b, 1.35, deck + 0.1, bz + 8.0, 4.4, grey.darkened(0.25))


static func _capital(b: TownModels.MB, length: float, beam: float, grey: Color, big: bool) -> void:
	var bow: float = -length * 0.5
	var deck: float = 2.4
	var light: Color = grey.lightened(0.10)
	var rad: float = 2.0 if big else 1.6
	var blen: float = 6.0 if big else 4.5
	var fore: Array = [0.12, 0.25] if big else [0.12, 0.23]
	var aft: Array = [0.82, 0.92] if big else [0.83]
	var k: int = 0
	for f in fore:
		_turret(b, 0.0, deck + (0.0 if k == 0 else 0.9), bow + length * f, rad, 3 if big else 2, blen, grey)
		k += 1
	for fz in aft:
		_turret(b, 0.0, deck + 0.0, bow + length * fz, rad, 3 if big else 2, blen, grey, -1.0)
	# tower: stacked decks of bridge, director and a fire-control top, with a tripod mast behind
	var tz: float = bow + length * 0.40
	b.box(-beam * 0.24, beam * 0.24, deck, deck + 3.4, tz - 3.2, tz + 3.4, light, true, grey.darkened(0.1))
	b.box(-beam * 0.18, beam * 0.18, deck + 3.4, deck + 5.8, tz - 2.4, tz + 2.2, light.lightened(0.05), true, grey.darkened(0.12))
	b.box(-beam * 0.30, beam * 0.30, deck + 3.4, deck + 3.7, tz - 2.8, tz + 1.0, grey.darkened(0.18), true)
	b.box(-beam * 0.12, beam * 0.12, deck + 5.8, deck + 7.6, tz - 1.6, tz + 1.0, grey, true)
	b.box(-0.6, 0.6, deck + 7.6, deck + 8.4, tz - 1.2, tz + 0.4, DARK, true)
	_mast(b, 0.0, deck + 5.8, tz + 4.2, 9.5 if big else 7.5, grey.darkened(0.3))
	# funnels (one trunked funnel on the big ship, two raked on the cruiser)
	if big:
		_funnel(b, 0.0, deck, bow + length * 0.55, 6.0, 1.9, 2.6, grey.darkened(0.30))
	else:
		_funnel(b, 0.0, deck, bow + length * 0.56, 5.2, 1.5, 2.2, grey.darkened(0.30))
		_funnel(b, 0.0, deck, bow + length * 0.67, 5.0, 1.5, 2.0, grey.darkened(0.30))
	# catapult and spotter on the quarterdeck, boat stowage, secondary guns on the beam
	b.box(-0.35, 0.35, deck, deck + 0.7, bow + length * 0.70, bow + length * 0.80, DARK, true)
	b.box(-1.4, 1.4, deck + 0.7, deck + 0.9, bow + length * 0.735, bow + length * 0.765, grey.darkened(0.3), true)
	for sx in [-1.0, 1.0]:
		for sz in [0.34, 0.47, 0.6]:
			b.box(sx * beam * 0.40 - 0.35, sx * beam * 0.40 + 0.35, deck, deck + 0.9, bow + length * sz - 0.35, bow + length * sz + 0.35, grey.darkened(0.15), true)
		_boat(b, sx * beam * 0.34, deck + 0.0, bow + length * 0.62, 5.0, grey.darkened(0.25))


static func _freighter(b: TownModels.MB, length: float, beam: float, hull_c: Color, collier: bool, allies: bool) -> void:
	var bow: float = -length * 0.5
	var deck: float = 3.6 if collier else 3.0
	var house: Color = WHITE if allies else Color(0.55, 0.56, 0.55)
	var hz: float = 12.0 if not collier else -1.0           # bridge house: aft on the freighter, amidships on the collier
	var hl: float = 8.0
	# forecastle and poop breaks
	b.box(-beam * 0.46, beam * 0.46, deck, deck + 1.1, bow + 0.5, bow + 6.0, hull_c.lightened(0.06), true, DECK)
	b.box(-beam * 0.46, beam * 0.46, deck, deck + 0.9, length * 0.5 - 8.0, length * 0.5 - 0.5, hull_c.lightened(0.06), true, DECK)
	# cargo hatches with coamings and tarpaulins, masts and derricks between them
	var hatches: Array = [-13.0, -5.0, 3.0] if not collier else [-17.0, -10.0, 7.0, 13.0]
	for hzv in hatches:
		b.box(-beam * 0.30, beam * 0.30, deck, deck + 0.55, hzv - 2.6, hzv + 2.6, DARK.lightened(0.1), false)
		b.box(-beam * 0.27, beam * 0.27, deck + 0.55, deck + 0.7, hzv - 2.4, hzv + 2.4, Color(0.22, 0.24, 0.17), true)
	for mz in ([-9.0, -1.0] if not collier else [-13.5, 10.0]):
		_mast(b, 0.0, deck, mz, 9.0)
		# a derrick boom slanting down toward the hatch
		for s in 2:
			b.face([Vector3(-0.07, deck + 7.0, mz - 0.4), Vector3(0.07, deck + 7.0, mz - 0.4), Vector3(0.07, deck + 1.2, mz + 3.4), Vector3(-0.07, deck + 1.2, mz + 3.4)], DARK, Vector3(0, 1, 1))
			break
	# the bridge house: three tiers, wheelhouse on top with a wing deck, boats on the boat deck, tall funnel
	b.box(-beam * 0.36, beam * 0.36, deck, deck + 2.8, hz - hl * 0.5, hz + hl * 0.5, house, true, house.darkened(0.1))
	b.box(-beam * 0.30, beam * 0.30, deck + 2.8, deck + 5.0, hz - hl * 0.5 + 0.8, hz + hl * 0.5 - 1.2, house.lightened(0.04), true, house.darkened(0.1))
	b.box(-beam * 0.40, beam * 0.40, deck + 5.0, deck + 5.25, hz - hl * 0.5 + 0.8, hz - hl * 0.5 + 3.2, house.darkened(0.2), true)
	b.box(-beam * 0.22, beam * 0.22, deck + 5.0, deck + 6.4, hz - hl * 0.5 + 1.0, hz - hl * 0.5 + 3.0, house.lightened(0.07), true, house.darkened(0.15))
	_funnel(b, 0.0, deck + 4.8, hz + hl * 0.5 - 1.8, 4.6, 1.2, 1.5, Color(0.55, 0.15, 0.12) if not collier else Color(0.12, 0.12, 0.12))
	for sx in [-1.0, 1.0]:
		_boat(b, sx * beam * 0.30, deck + 4.9, hz + 0.6, 4.4, hull_c.lightened(0.2))
	# a defensive gun on the poop (DEMS) for the Allied ships
	if allies:
		_turret(b, 0.0, deck + 0.9, length * 0.5 - 3.0, 0.6, 1, 1.6, DARK.lightened(0.15), -1.0)


static func _trawler(b: TownModels.MB, length: float, beam: float, tc: Color) -> void:
	var deck: float = 1.8
	b.box(-beam * 0.44, beam * 0.44, deck, deck + 0.9, -length * 0.5 + 0.5, -length * 0.5 + 4.5, tc, true, DECK)
	b.box(-beam * 0.30, beam * 0.30, deck, deck + 2.2, 0.0, 3.8, tc.lightened(0.12), true, tc.darkened(0.1))
	b.box(-beam * 0.24, beam * 0.24, deck + 2.2, deck + 3.2, 0.5, 2.6, tc.lightened(0.15), true, tc.darkened(0.1))
	_funnel(b, 0.0, deck, 5.0, 3.4, 0.7, 0.9, Color(0.14, 0.14, 0.15))
	_mast(b, 0.0, deck, -2.0, 6.5)
	_turret(b, 0.0, deck + 0.9, -length * 0.5 + 3.2, 0.8, 1, 2.0, tc.darkened(0.2))
	b.box(-beam * 0.30, beam * 0.30, deck, deck + 0.5, length * 0.5 - 5.0, length * 0.5 - 1.0, tc.darkened(0.2), true)
	_boat(b, 0.0, deck + 0.0, length * 0.5 - 3.0, 3.0, tc.darkened(0.25))


static func _ferry(b: TownModels.MB, length: float, beam: float) -> void:
	var wh: Color = WHITE.lightened(0.04)
	var deck: float = 2.4
	b.box(-beam * 0.40, beam * 0.40, deck, deck + 2.8, -length * 0.28, length * 0.34, wh, true, wh.darkened(0.12))
	b.box(-beam * 0.34, beam * 0.34, deck + 2.8, deck + 5.2, -length * 0.22, length * 0.26, wh.darkened(0.03), true, wh.darkened(0.12))
	b.box(-beam * 0.26, beam * 0.26, deck + 5.2, deck + 6.8, -length * 0.20, -length * 0.02, wh.darkened(0.08), true, wh.darkened(0.14))
	b.box(-beam * 0.42, beam * 0.42, deck + 5.2, deck + 5.4, -length * 0.20, -length * 0.08, wh.darkened(0.25), true)
	_funnel(b, 0.0, deck + 5.0, length * 0.10, 4.2, 1.25, 1.7, Color(0.75, 0.55, 0.20))
	b.box(-beam * 0.24, beam * 0.24, deck + 5.2, deck + 5.5, length * 0.20, length * 0.32, wh.darkened(0.15), true)
	for sx in [-1.0, 1.0]:
		b.box(sx * beam * 0.41 - 0.12, sx * beam * 0.41 + 0.12, deck + 2.9, deck + 3.5, -length * 0.20, length * 0.24, DARK.lightened(0.1), true)
		for k in 4:
			_boat(b, sx * beam * 0.33, deck + 5.3, -4.0 + float(k) * 4.0, 3.6, wh.darkened(0.3))
	_mast(b, 0.0, deck + 6.8, -length * 0.16, 6.0)


static func _landing_craft(b: TownModels.MB, length: float, beam: float) -> void:
	var col: Color = Color(0.34, 0.37, 0.30)
	var deck: float = 1.4
	# open well with high sides, a small wheelhouse aft and a raised bow ramp
	b.box(-beam * 0.5, -beam * 0.5 + 0.35, deck, deck + 0.9, -length * 0.5 + 1.0, length * 0.5 - 1.0, col, true)
	b.box(beam * 0.5 - 0.35, beam * 0.5, deck, deck + 0.9, -length * 0.5 + 1.0, length * 0.5 - 1.0, col, true)
	b.box(-beam * 0.36, beam * 0.36, deck, deck + 0.2, -length * 0.5 + 0.8, length * 0.5 - 3.4, col.darkened(0.2), true)
	b.box(-beam * 0.42, beam * 0.42, deck, deck + 2.4, length * 0.5 - 3.4, length * 0.5 - 0.4, col.lightened(0.1), true, col.darkened(0.1))
	b.face([Vector3(-beam * 0.44, deck + 1.6, -length * 0.5 + 0.2), Vector3(beam * 0.44, deck + 1.6, -length * 0.5 + 0.2), Vector3(beam * 0.44, deck + 0.1, -length * 0.5 + 1.2), Vector3(-beam * 0.44, deck + 0.1, -length * 0.5 + 1.2)], col.darkened(0.25), Vector3(0, 0.6, -1))
	b.box(-0.2, 0.2, deck + 2.4, deck + 3.4, length * 0.5 - 2.2, length * 0.5 - 1.8, DARK, true)


static func _fishing_boat(b: TownModels.MB, length: float, beam: float) -> void:
	var cab: Color = Color(0.62, 0.55, 0.42)
	b.box(-beam * 0.26, beam * 0.26, 1.0, 2.4, 0.5, 3.4, cab, true, cab.darkened(0.2))
	b.box(-beam * 0.22, beam * 0.22, 1.5, 1.9, 0.45, 0.55, DARK, true)
	_mast(b, 0.0, 1.0, -1.6, 5.4, Color(0.34, 0.28, 0.20))
	b.box(-beam * 0.30, beam * 0.30, 1.0, 1.3, -length * 0.5 + 1.5, -1.2, Color(0.30, 0.26, 0.20), true)
	b.box(-0.05, 0.05, 1.0, 2.4, length * 0.5 - 0.6, length * 0.5 - 0.5, DARK, true)
