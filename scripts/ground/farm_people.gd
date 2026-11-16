class_name FarmPeople
extends RefCounted
## Phase 2 of the living world: life on the farms and in the fields, England and France. A few work parties a
## countryside tile, planned on the tile worker (like AirfieldPeople.village_plan) INSIDE the fields near the farms,
## and spawned with the tile as one MultiMesh of figures (AirfieldPeople.spawn, so the farm folk dive for cover
## under enemy aircraft like everyone else) plus one small MultiMesh per prop type: a horse led with a hay cart, a
## horse and cart driven from the seat, a pair of horses with a plough, a Fordson tractor with its plough, and the
## still things - stooks, haycocks, a haystack.
##
## The work follows the farmland crop cycle (terrain_chunk_manager.gd SEASON_CENTER, EraClock.month()): ploughing
## with horses (and the odd tractor) in autumn and winter, sowing and hoeing in spring, haymaking in early summer,
## harvest gangs among the stooks from July to September, a cart of fodder to the stock in the dead of winter.
##
## Everything with a horse or an engine moves rigidly with its man: the figure and the prop are spawned from the same
## entry (position, direction, beat length, speed, phase) and both shaders run the same beat maths (see
## shaders/farm_props.gdshader), so the man at the horse's head, the driver on the seat and the ploughman at the
## handles keep their place on the straight and through the turn at the headland. The prop mesh is built around the
## man's origin: the horse beside and behind the leader, the cart under the driver, the plough team before the
## ploughman.
##
## Placement: a spot must be cropland or grass (LandCover), at least FIELD_CLEAR from every field boundary (the hedge
## band: the CPU mirror of the terrain's field lattice, Scatter.field_edge), off roads, rivers, lakes and the sea and
## clear of every house of the tile, along its whole beat; counts scale with AirfieldPeople.density() and the month.

enum Prop { HORSE_LED, CART_LED, CART_DRIVEN, PLOUGH_TEAM, TRACTOR }
enum Still { STOOK, HAYCOCK, HAYSTACK }
enum Job { PLOUGH_HORSE, PLOUGH_TRACTOR, SOW, HAY, HARVEST, FEED }

const FIELD_CLEAR: float = 9.0        # m from any field boundary: the hedge and its verge stay free of work parties
const ROAD_CLEAR: float = 7.0
const HOUSE_PAD: float = 3.0
const END_MARGIN: float = 9.0         # the team swings round at each end of its beat: that much free beyond it
const CART_SEAT: float = 1.04         # the driver's seat on a cart, m above the ground (mesh metres)
const TRACTOR_SEAT: float = 1.10      # ... and on the tractor
const MEN_PER_GROUP_MAX: int = 12

## Weights of the kinds of work for each month (rows January .. December; columns in the Job order): horse ploughing,
## tractor ploughing, sowing and hoeing, haymaking, harvest, fodder carting. The year follows the terrain's crop cycle:
## ploughed in October, sown through the winter and spring, hay in June, harvest and stubble in August and September.
const JOB_W: Array = [
	[0.30, 0.20, 0.00, 0.00, 0.00, 0.80],
	[0.50, 0.30, 0.00, 0.00, 0.00, 0.60],
	[0.50, 0.50, 0.60, 0.00, 0.00, 0.20],
	[0.10, 0.30, 1.00, 0.00, 0.00, 0.00],
	[0.00, 0.10, 1.00, 0.00, 0.00, 0.00],
	[0.00, 0.00, 0.50, 1.00, 0.00, 0.00],
	[0.00, 0.00, 0.00, 0.70, 0.40, 0.00],
	[0.00, 0.00, 0.00, 0.00, 1.00, 0.00],
	[0.10, 0.00, 0.00, 0.00, 1.00, 0.00],
	[1.00, 0.50, 0.00, 0.00, 0.20, 0.00],
	[1.00, 0.60, 0.00, 0.00, 0.00, 0.00],
	[0.70, 0.40, 0.00, 0.00, 0.00, 0.40],
]

## How busy the fields are in each month (a multiplier on the work parties of a tile): thin in the dead of winter,
## busiest at the harvest and the autumn ploughing.
const SEASON_BUSY: Array = [0.5, 0.6, 0.8, 0.9, 0.9, 1.0, 1.0, 1.2, 1.2, 1.1, 0.9, 0.6]

static var _prop_meshes: Dictionary = {}
static var _still_meshes: Dictionary = {}
static var _prop_mats: Dictionary = {}
static var _still_mat: StandardMaterial3D
static var _prop_shader: Shader
static var _shot_made: bool = false


# ------------------------------------------------------------------ the plan (tile worker)

## How many work parties a countryside tile gets: about two a tile on Medium, more on High, fewer in the slack months.
static func group_target(dens: float, month: int) -> int:
	return int(round(2.0 * dens * float(SEASON_BUSY[clampi(month, 1, 12) - 1])))


static var _short_cached: int = -1


## True when the game was started with --farm-shot-short (the debug shot's team stays within a few metres of its centre).
static func _short_beats() -> bool:
	if _short_cached < 0:
		_short_cached = 0
		for a in OS.get_cmdline_user_args():
			if a == "--farm-shot-short":
				_short_cached = 1
	return _short_cached == 1


static func _pick_job(w: Array, rng: RandomNumberGenerator) -> int:
	var s: float = 0.0
	for x in w:
		s += float(x)
	var r: float = rng.randf() * s
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0 and float(w[i]) > 0.0:
			return i
	return 0


## The outfit of one farm hand: England has the farmer, the Women's Land Army girl and the farm boy; France the farmer
## in his blue smock and beret, his wife in a headscarf and the boy.
static func _worker_dress(france: bool, rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if france:
		return AirfieldPeople.FARM_FARMER_FR if r < 0.58 else (AirfieldPeople.FARM_WOMAN_FR if r < 0.84 else AirfieldPeople.FARM_BOY)
	return AirfieldPeople.FARM_FARMER if r < 0.50 else (AirfieldPeople.FARM_LAND_GIRL if r < 0.84 else AirfieldPeople.FARM_BOY)


## The man who leads, drives or follows a team: a farmer (not the boy, not the women).
static func _driver_dress(france: bool, rng: RandomNumberGenerator) -> int:
	if france:
		return AirfieldPeople.FARM_FARMER_FR
	return AirfieldPeople.FARM_FARMER if rng.randf() < 0.8 else AirfieldPeople.FARM_LAND_GIRL


## May work be done at p? Cropland or grass, on land, off roads and rivers and lakes, clear of the houses, inside
## `bounds`, and clear of every field boundary (hedge band).
static func _spot_ok(p: Vector2, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> bool:
	if not bounds.has_point(p):
		return false
	var cls: int = LandCover.class_at(p.x, p.y)
	if cls != 40 and cls != 30:
		return false
	if GroundKit.raw_y(p.x, p.y) <= 1.5:
		return false
	if Scatter.in_lake(p.x, p.y):
		return false
	if hm.blocked(p):
		return false
	if RoadMesh.near_road(p, ROAD_CLEAR) or RiverMesh.near_river(p):
		return false
	var e: Dictionary = Scatter.field_edge(p)
	if e.is_empty():
		return false
	return float(e["dist"]) > FIELD_CLEAR


static func _line_ok(p0: Vector2, p1: Vector2, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> bool:
	var steps: int = int(p0.distance_to(p1) / 5.0) + 1
	for k in steps + 1:
		if not _spot_ok(p0.lerp(p1, float(k) / float(steps)), hm, bounds):
			return false
	return true


## The longest beat (lmax, shortening by a quarter at a time down to lmin) centred on c along dir that is free along its
## whole length and for END_MARGIN beyond both ends. 0 if there is none.
static func _find_line(c: Vector2, dir: Vector2, lmin: float, lmax: float, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> float:
	if _short_beats():
		lmin = minf(lmin, 14.0)               # (--farm-shot: beats of at most 26 m, so a team stays in front of the camera)
		lmax = minf(lmax, 26.0)
	var ln: float = lmax
	while ln >= lmin:
		var a: Vector2 = c - dir * (ln * 0.5 + END_MARGIN)
		var b: Vector2 = c + dir * (ln * 0.5 + END_MARGIN)
		if _line_ok(a, b, hm, bounds):
			var ya: float = GroundKit.ground_y(c.x - dir.x * ln * 0.5, c.y - dir.y * ln * 0.5)
			var yb: float = GroundKit.ground_y(c.x + dir.x * ln * 0.5, c.y + dir.y * ln * 0.5)
			if absf(ya - yb) <= 6.0:
				return ln
		ln *= 0.75
	return 0.0


## One figure standing at his work: forking, hoeing, stooking.
static func _stand(out: Dictionary, p: Vector2, face: Vector2, kind: int, dress: int) -> void:
	var f: Vector2 = face.normalized() if face.length() > 0.01 else Vector2.DOWN
	var gy: float = GroundKit.ground_y(p.x, p.y)
	(out["men"] as Array).append([Vector3(p.x, 0.0, p.y), Vector3(f.x, 0.0, f.y), kind, 0.0, -1.0, 0.0, false, null, 0.0, gy, gy, dress])


## A prop and its man on the same beat: the man (kind LEAD_HORSE, DRIVE_CART or PLOUGHMAN) is a figure at the prop's
## origin, walking the same beat with the same speed and phase, so the two stay in step.
static func _team(out: Dictionary, prop: int, p0: Vector2, dir: Vector2, ln: float, spd: float, rng: RandomNumberGenerator,
		man_kind: int, man_dress: int, coat: int, loaded: bool) -> void:
	var ph: float = rng.randf()
	var p1: Vector2 = p0 + dir * ln
	var y0: float = GroundKit.ground_y(p0.x, p0.y)
	var y1: float = GroundKit.ground_y(p1.x, p1.y)
	var elev: float = 0.0
	if man_kind == AirfieldPeople.Kind.DRIVE_CART:
		elev = ((TRACTOR_SEAT if prop == Prop.TRACTOR else CART_SEAT) - 0.01) * AirfieldPeople.MAN
	(out["men"] as Array).append([Vector3(p0.x, 0.0, p0.y), Vector3(dir.x, 0.0, dir.y), man_kind, ln, ph, spd, false, null, elev, y0, y1, man_dress])
	var props: Dictionary = out["props"]
	var lst: Array = props.get(prop, [])
	lst.append([Vector3(p0.x, 0.0, p0.y), Vector3(dir.x, 0.0, dir.y), ln, ph, spd, y0, y1, coat + (4 if loaded else 0)])
	props[prop] = lst


static func _still(out: Dictionary, kind: int, p: Vector2, yaw: float, sc: float) -> void:
	var st: Dictionary = out["still"]
	var lst: Array = st.get(kind, [])
	lst.append([Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y), yaw, sc])
	st[kind] = lst


## Ploughing: a pair of horses with the ploughman behind the share, or a Fordson with its trailed plough, up and down a
## furrow along the field.
static func _job_plough(out: Dictionary, c: Vector2, dir: Vector2, tractor: bool, france: bool, rng: RandomNumberGenerator, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> bool:
	var ln: float = _find_line(c, dir, 36.0, 110.0, hm, bounds)
	if ln <= 0.0:
		return false
	var p0: Vector2 = c - dir * (ln * 0.5)
	if tractor:
		_team(out, Prop.TRACTOR, p0, dir, ln, rng.randf_range(1.4, 1.9), rng, AirfieldPeople.Kind.DRIVE_CART, _driver_dress(france, rng), 0, false)
	else:
		_team(out, Prop.PLOUGH_TEAM, p0, dir, ln, rng.randf_range(0.85, 1.05), rng, AirfieldPeople.Kind.PLOUGHMAN, _driver_dress(france, rng), rng.randi() % 4, false)
	return true


## Sowing and hoeing: a gang abreast across the field, bent over their hoes, chopping at the weeds. A boy or a Land
## Army girl among the men.
static func _job_hoe(out: Dictionary, c: Vector2, dir: Vector2, france: bool, rng: RandomNumberGenerator, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> bool:
	var n: int = rng.randi_range(3, 6)
	var across := Vector2(-dir.y, dir.x)
	var placed: int = 0
	var made: Array = []
	for k in n:
		var p: Vector2 = c + across * ((float(k) - 0.5 * float(n - 1)) * 2.4) + dir * rng.randf_range(-0.7, 0.7)
		if _spot_ok(p, hm, bounds):
			made.append(p)
	if made.size() < 2:
		return false
	for p2 in made:
		_stand(out, p2, dir, AirfieldPeople.Kind.HOE, _worker_dress(france, rng))
		placed += 1
	return placed >= 2


## Haymaking: a cart of hay (led, or driven from the seat) working along a row of haycocks, with a few hands forking
## the hay up to it.
static func _job_hay(out: Dictionary, c: Vector2, dir: Vector2, france: bool, rng: RandomNumberGenerator, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> bool:
	var ln: float = _find_line(c, dir, 30.0, 64.0, hm, bounds)
	if ln <= 0.0:
		return false
	var p0: Vector2 = c - dir * (ln * 0.5)
	var across := Vector2(-dir.y, dir.x)
	var dress: int = _driver_dress(france, rng)
	if rng.randf() < 0.5:
		_team(out, Prop.CART_LED, p0, dir, ln, rng.randf_range(0.95, 1.15), rng, AirfieldPeople.Kind.LEAD_HORSE, dress, rng.randi() % 4, true)
	else:
		_team(out, Prop.CART_DRIVEN, p0, dir, ln, rng.randf_range(1.2, 1.5), rng, AirfieldPeople.Kind.DRIVE_CART, dress, rng.randi() % 4, true)
	var forks: int = rng.randi_range(2, 4)
	for k in forks:
		var side: float = 1.0 if k % 2 == 0 else -1.0
		var p: Vector2 = c + across * (side * rng.randf_range(4.0, 5.6)) + dir * rng.randf_range(-7.0, 7.0)
		if _spot_ok(p, hm, bounds):
			_stand(out, p, -across * side, AirfieldPeople.Kind.PITCHFORK, _worker_dress(france, rng))
	var cocks: int = rng.randi_range(3, 7)
	for k2 in cocks:
		var q: Vector2 = c + across * (rng.randf_range(9.0, 12.0) * (1.0 if k2 % 2 == 0 else -1.0)) + dir * (float(k2) * 5.0 - 15.0 + rng.randf_range(-1.5, 1.5))
		if _spot_ok(q, hm, bounds):
			_still(out, Still.HAYCOCK, q, rng.randf() * TAU, rng.randf_range(0.85, 1.2))
	return true


## Harvest: a row of stooks, a gang bent to the sheaves and a couple forking them up to a loaded cart on the headland.
static func _job_harvest(out: Dictionary, c: Vector2, dir: Vector2, france: bool, rng: RandomNumberGenerator, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> bool:
	var across := Vector2(-dir.y, dir.x)
	var stooks: int = rng.randi_range(6, 10)
	var row: Array = []
	for k in stooks:
		var p: Vector2 = c + dir * ((float(k) - 0.5 * float(stooks - 1)) * 5.0) + across * rng.randf_range(-0.4, 0.4)
		if _spot_ok(p, hm, bounds):
			row.append(p)
	if row.size() < 3:
		return false
	for sp0 in row:
		_still(out, Still.STOOK, sp0, rng.randf() * TAU, rng.randf_range(0.9, 1.15))
	var bent: int = mini(rng.randi_range(2, 4), row.size())
	for k2 in bent:
		var sp: Vector2 = row[(k2 * 2 + rng.randi() % 2) % row.size()]
		var side: float = 1.0 if k2 % 2 == 0 else -1.0
		var p2: Vector2 = sp + across * (side * 1.5)
		if _spot_ok(p2, hm, bounds):
			_stand(out, p2, -across * side, AirfieldPeople.Kind.WORK, _worker_dress(france, rng))
	# the cart on the next row over, loaded by two with forks
	var cc: Vector2 = c + across * 10.0
	var ln: float = _find_line(cc, dir, 18.0, 34.0, hm, bounds)
	if ln > 0.0:
		var p0: Vector2 = cc - dir * (ln * 0.5)
		var dress: int = _driver_dress(france, rng)
		if rng.randf() < 0.5:
			_team(out, Prop.CART_DRIVEN, p0, dir, ln, rng.randf_range(0.9, 1.2), rng, AirfieldPeople.Kind.DRIVE_CART, dress, rng.randi() % 4, true)
		else:
			_team(out, Prop.CART_LED, p0, dir, ln, rng.randf_range(0.9, 1.1), rng, AirfieldPeople.Kind.LEAD_HORSE, dress, rng.randi() % 4, true)
		for k3 in 2:
			var side2: float = 1.0 if k3 == 0 else -1.0
			var fp: Vector2 = cc + across * (side2 * 4.2) + dir * rng.randf_range(-5.0, 5.0)
			if _spot_ok(fp, hm, bounds):
				_stand(out, fp, -across * side2, AirfieldPeople.Kind.PITCHFORK, _worker_dress(france, rng))
	return true


## Fodder in the dead of winter: a haystack in the field, a cart loaded from it and two hands with forks.
static func _job_feed(out: Dictionary, c: Vector2, dir: Vector2, france: bool, rng: RandomNumberGenerator, hm: AirfieldPeople.HouseMap, bounds: Rect2) -> bool:
	var ln: float = _find_line(c, dir, 18.0, 34.0, hm, bounds)
	if ln <= 0.0:
		return false
	var across := Vector2(-dir.y, dir.x)
	var stack: Vector2 = c + across * 8.0
	if not _spot_ok(stack, hm, bounds) or not _spot_ok(stack + dir * 3.0, hm, bounds) or not _spot_ok(stack - dir * 3.0, hm, bounds):
		return false
	_still(out, Still.HAYSTACK, stack, atan2(-dir.y, dir.x), rng.randf_range(0.9, 1.1))
	var p0: Vector2 = c - dir * (ln * 0.5)
	_team(out, Prop.CART_LED, p0, dir, ln, rng.randf_range(0.95, 1.15), rng, AirfieldPeople.Kind.LEAD_HORSE, _driver_dress(france, rng), rng.randi() % 4, true)
	for k in 2:
		var side: float = 1.0 if k == 0 else -1.0
		var fp: Vector2 = stack - across * 4.0 + dir * (side * 3.2)
		if _spot_ok(fp, hm, bounds):
			_stand(out, fp, across, AirfieldPeople.Kind.PITCHFORK, _worker_dress(france, rng))
	return true


## The work parties of one countryside tile. `org` / `cell` are the tile's corner and size, `houses` the tile's own house
## transform lists (Scatter.tile_landcover_data "house_xf": clear of them, and the farms they make are where the work
## is), `dens` AirfieldPeople.density(), `month` EraClock.month() and `france` whether the tile lies on the continent
## (OccupationLife.continental). Call on the tile worker before RoadMesh.clear_block (roads are kept clear).
## Returns {"men": entries for AirfieldPeople.spawn, "props": {Prop: entries}, "still": {Still: entries},
## "groups": [{"job", "pos", "dir"}]} - plain data, nothing here touches the scene tree.
static func plan(org: Vector2, cell: float, houses: Array, seed_v: int, dens: float, month: int, france: bool) -> Dictionary:
	var out: Dictionary = {"men": [], "props": {}, "still": {}, "groups": []}
	var target: int = group_target(dens, month)
	if target <= 0:
		return out
	var w: Array = JOB_W[clampi(month, 1, 12) - 1]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var hm := AirfieldPeople.HouseMap.new()
	hm.pad = HOUSE_PAD
	var all: Array = []
	for lst in houses:
		for t in (lst as Array):
			all.append(t)
			hm.add_xf(t as Transform3D)
	var bounds := Rect2(org + Vector2(40.0, 40.0), Vector2(cell - 80.0, cell - 80.0))
	if france:
		w = w.duplicate()
		w[1] = float(w[1]) * 0.3          # few tractors on the French farms
	for gi in target:
		for attempt in 14:
			# near a farm when the tile has one, else anywhere in the tile
			var c: Vector2
			if not all.is_empty() and rng.randf() < 0.75:
				var h: Transform3D = all[rng.randi() % all.size()]
				var a: float = rng.randf() * TAU
				c = Vector2(h.origin.x, h.origin.z) + Vector2(cos(a), sin(a)) * rng.randf_range(45.0, 230.0)
			else:
				c = org + Vector2(rng.randf_range(60.0, cell - 60.0), rng.randf_range(60.0, cell - 60.0))
			if not _spot_ok(c, hm, bounds):
				continue
			var e: Dictionary = Scatter.field_edge(c)
			if e.is_empty():
				continue
			var dir: Vector2 = e["tan"]
			if rng.randf() < 0.5:
				dir = -dir
			var job: int = _pick_job(w, rng)
			# ploughing, sowing and the harvest are on cropland (class 40); hay and fodder may be on a meadow too
			if job != Job.HAY and job != Job.FEED and LandCover.class_at(c.x, c.y) != 40:
				continue
			var ok: bool = false
			var before: int = (out["men"] as Array).size()
			match job:
				Job.PLOUGH_HORSE:
					ok = _job_plough(out, c, dir, false, france, rng, hm, bounds)
				Job.PLOUGH_TRACTOR:
					ok = _job_plough(out, c, dir, true, france, rng, hm, bounds)
				Job.SOW:
					ok = _job_hoe(out, c, dir, france, rng, hm, bounds)
				Job.HAY:
					ok = _job_hay(out, c, dir, france, rng, hm, bounds)
				Job.HARVEST:
					ok = _job_harvest(out, c, dir, france, rng, hm, bounds)
				Job.FEED:
					ok = _job_feed(out, c, dir, france, rng, hm, bounds)
			if ok:
				(out["groups"] as Array).append({"job": job, "pos": Vector3(c.x, GroundKit.ground_y(c.x, c.y), c.y), "dir": Vector3(dir.x, 0.0, dir.y), "men": (out["men"] as Array).size() - before})
				break
	return out


# ------------------------------------------------------------------ the prop meshes

static func _bx(a: AirfieldPeople._Acc, size: Vector3, c: Vector3, col: Color, bas: Basis = Basis.IDENTITY, part: int = 0, limb: int = 0, lower: bool = false) -> void:
	AirfieldPeople._box(a, size, c, col, part, limb, lower, bas)


static func _ell(a: AirfieldPeople._Acc, c: Vector3, rad: Vector3, col: Color, part: int = 0, limb: int = 0, lower: bool = false) -> void:
	AirfieldPeople._ball(a, c, 1.0, rad, part, limb, lower, col)


## A tapered rod from p0 (radius r0) to p1 (radius r1).
static func _seg(a: AirfieldPeople._Acc, p0: Vector3, p1: Vector3, r0: float, r1: float, col: Color, part: int = 0, limb: int = 0, lower: bool = false) -> void:
	var d: Vector3 = p1 - p0
	var ln: float = d.length()
	if ln < 0.001:
		return
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = ln
	cm.radial_segments = 6
	cm.rings = 1
	var u: Vector3 = d / ln
	var bas: Basis = Basis(Vector3.RIGHT, PI) if u.dot(Vector3.UP) < -0.999 else Basis(Quaternion(Vector3.UP, u))
	AirfieldPeople._part(a, cm, Transform3D(bas, (p0 + p1) * 0.5), col, part, limb, lower)


## A wheel standing on its edge, axle along x.
static func _wheel(a: AirfieldPeople._Acc, c: Vector3, r: float, w: float, col: Color, hub: Color) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = w
	cm.radial_segments = 12
	cm.rings = 1
	AirfieldPeople._part(a, cm, Transform3D(Basis(Vector3.BACK, PI * 0.5), c), col, 0, 0, false)
	var hm := CylinderMesh.new()
	hm.top_radius = r * 0.22
	hm.bottom_radius = r * 0.22
	hm.height = w * 1.5
	hm.radial_segments = 6
	hm.rings = 1
	AirfieldPeople._part(a, hm, Transform3D(Basis(Vector3.BACK, PI * 0.5), c), hub, 0, 0, false)


## A draught horse standing on the ground at (cx, cz), facing -Z. Legs carry limb 1-4 (hind left, fore left, hind right,
## fore right) + `off` (10 for the second horse of a team), the tail 5, the head and neck 6; the coat is part 1, the mane
## and tail part 2 (the shader gives them their colours).
static func _horse(a: AirfieldPeople._Acc, cx: float, cz: float, off: int) -> void:
	var w := Color.WHITE
	var leather := Color(0.16, 0.10, 0.06)
	var hoof := Color(0.06, 0.05, 0.045)
	_ell(a, Vector3(cx, 1.27, cz - 0.05), Vector3(0.34, 0.39, 0.82), w, 1)                  # barrel
	_ell(a, Vector3(cx, 1.30, cz + 0.55), Vector3(0.35, 0.38, 0.40), w, 1)                  # quarters
	_ell(a, Vector3(cx, 1.28, cz - 0.58), Vector3(0.31, 0.39, 0.34), w, 1)                  # chest
	_seg(a, Vector3(cx, 1.40, cz - 0.66), Vector3(cx, 1.96, cz - 1.06), 0.18, 0.115, w, 1, 6 + off)       # neck
	_ell(a, Vector3(cx, 1.97, cz - 1.12), Vector3(0.13, 0.15, 0.17), w, 1, 6 + off)                       # poll
	_seg(a, Vector3(cx, 1.94, cz - 1.10), Vector3(cx, 1.56, cz - 1.52), 0.125, 0.07, w, 1, 6 + off)        # head and muzzle
	for ex in [-0.07, 0.07]:
		_seg(a, Vector3(cx + ex, 2.08, cz - 1.06), Vector3(cx + ex, 2.26, cz - 1.08), 0.035, 0.012, w, 1, 6 + off)   # ears
	_seg(a, Vector3(cx, 1.62, cz - 0.80), Vector3(cx, 2.00, cz - 1.08), 0.05, 0.05, w, 2, 6 + off)         # mane along the crest
	_seg(a, Vector3(cx, 1.46, cz + 0.93), Vector3(cx, 0.72, cz + 1.10), 0.07, 0.035, w, 2, 5 + off)        # tail
	_ell(a, Vector3(cx, 1.50, cz - 0.76), Vector3(0.22, 0.28, 0.13), leather, 0, 6 + off)                  # the collar
	var legs: Array = [[1, -0.19, 0.55], [2, -0.19, -0.50], [3, 0.19, 0.55], [4, 0.19, -0.50]]
	for lg in legs:
		var id: int = int(lg[0]) + off
		var lx: float = cx + float(lg[1])
		var lz: float = cz + float(lg[2])
		_seg(a, Vector3(lx, 1.08, lz), Vector3(lx, 0.52, lz), 0.105, 0.065, w, 1, id, false)             # thigh / forearm
		_seg(a, Vector3(lx, 0.52, lz), Vector3(lx, 0.10, lz), 0.055, 0.045, w, 1, id, true)              # cannon
		_bx(a, Vector3(0.11, 0.10, 0.14), Vector3(lx, 0.05, lz - 0.01), hoof, Basis.IDENTITY, 0, id, true)   # hoof


## A farm cart (a tumbril): floor, sideboards, tailboard, two big wooden wheels, shafts running forward from z = shaft_z.
## fz is the z of its front edge, cx the centre line. With `seat` the driver's board lies across the front (at the
## prop's origin) and a toeboard sloping forward under his boots, else a front board; a hay or sheaf load is part 4.
static func _cart(a: AirfieldPeople._Acc, cx: float, fz: float, shaft_z: float, seat: bool) -> void:
	var wood := Color(0.50, 0.37, 0.21)
	var dark := Color(0.30, 0.22, 0.12)
	_bx(a, Vector3(1.5, 0.06, 2.3), Vector3(cx, 0.76, fz + 1.15), wood)
	for sx in [-0.75, 0.75]:
		_bx(a, Vector3(0.05, 0.38, 2.3), Vector3(cx + sx, 0.98, fz + 1.15), wood)
	_bx(a, Vector3(1.5, 0.38, 0.05), Vector3(cx, 0.98, fz + 2.3), wood)
	for wx in [-0.86, 0.86]:
		_wheel(a, Vector3(cx + wx, 0.62, fz + 1.0), 0.62, 0.07, Color(0.42, 0.30, 0.16), dark)
	for sx2 in [-0.55, 0.55]:
		_seg(a, Vector3(cx + sx2, 0.95, shaft_z), Vector3(cx + sx2, 0.86, fz + 1.2), 0.03, 0.03, dark)
	if seat:
		_bx(a, Vector3(1.3, 0.05, 0.32), Vector3(cx, 1.015, fz + 0.30), wood)
		_bx(a, Vector3(0.9, 0.05, 0.50), Vector3(cx, 0.56, fz - 0.55), wood, Basis(Vector3.RIGHT, 0.25))
	else:
		_bx(a, Vector3(1.5, 0.45, 0.05), Vector3(cx, 1.0, fz), wood)
	var hay := Color(0.66, 0.56, 0.25)
	_ell(a, Vector3(cx, 1.22, fz + 1.25), Vector3(0.80, 0.50, 1.20), hay, 4)
	_ell(a, Vector3(cx, 1.60, fz + 1.20), Vector3(0.62, 0.32, 0.90), hay.lightened(0.10), 4)


## The led horse with its cart (type CART_LED, and the horse alone, HORSE_LED): the leader (a LEAD_HORSE figure) is the
## origin, his right hand at the halter, the horse beside and behind him.
static func _led_mesh(with_cart: bool) -> ArrayMesh:
	var a := AirfieldPeople._Acc.new()
	_horse(a, 0.80, 0.70, 0)
	_seg(a, Vector3(0.27, 1.12, -0.52), Vector3(0.78, 1.60, -0.92), 0.012, 0.012, Color(0.20, 0.14, 0.08))      # the lead rope
	if with_cart:
		_cart(a, 0.80, 2.45, 0.80, false)
	return _finish(a)


## The driven cart (type CART_DRIVEN): the driver (a DRIVE_CART figure) sits at the origin on the board across the cart's
## front, the horse some three metres ahead in the shafts.
static func _driven_mesh() -> ArrayMesh:
	var a := AirfieldPeople._Acc.new()
	_horse(a, 0.0, -2.75, 0)
	_cart(a, 0.0, -0.20, -2.85, true)
	return _finish(a)


## The plough team (type PLOUGH_TEAM): two horses abreast before a single-furrow plough and the ploughman (a PLOUGHMAN
## figure) at the origin with his hands on the handles.
static func _plough_mesh() -> ArrayMesh:
	var a := AirfieldPeople._Acc.new()
	var dark := Color(0.14, 0.14, 0.15)
	var wood := Color(0.40, 0.30, 0.17)
	_horse(a, -0.62, -5.0, 0)
	_horse(a, 0.62, -5.0, 10)
	# the plough: handles up to the ploughman's hands, the beam out to the swingletree, share, mouldboard and a land wheel
	for hx in [-0.17, 0.17]:
		_seg(a, Vector3(hx, 0.98, -0.46), Vector3(hx * 0.5, 0.40, -1.75), 0.022, 0.022, wood)
	_seg(a, Vector3(0.0, 0.50, -1.60), Vector3(0.0, 0.74, -3.50), 0.04, 0.04, dark)
	_bx(a, Vector3(0.28, 0.08, 0.60), Vector3(0.0, 0.06, -1.85), dark)                                              # the share
	_bx(a, Vector3(0.05, 0.36, 0.70), Vector3(0.20, 0.26, -1.70), dark, Basis(Vector3.BACK, -0.45))                # the mouldboard
	_bx(a, Vector3(0.04, 0.55, 0.06), Vector3(-0.04, 0.34, -1.55), dark)                                            # the coulter
	_wheel(a, Vector3(0.0, 0.20, -3.05), 0.20, 0.05, dark, dark)
	_bx(a, Vector3(1.46, 0.05, 0.05), Vector3(0.0, 0.78, -3.65), wood)                                              # the swingletree
	for cx in [-0.62, 0.62]:
		_seg(a, Vector3(cx, 0.78, -3.65), Vector3(cx, 1.30, -5.75), 0.012, 0.012, Color(0.22, 0.22, 0.24))         # the chain to the hames
	return _finish(a)


## A Fordson-like tractor with a trailed two-furrow plough (type TRACTOR): the driver (a DRIVE_CART figure) sits at the
## origin on the seat over the rear axle.
static func _tractor_mesh() -> ArrayMesh:
	var a := AirfieldPeople._Acc.new()
	var blue := Color(0.15, 0.22, 0.38)
	var orange := Color(0.66, 0.28, 0.07)
	var grey := Color(0.20, 0.20, 0.22)
	var black := Color(0.06, 0.06, 0.06)
	_bx(a, Vector3(0.58, 0.50, 1.05), Vector3(0.0, 0.62, -0.05), blue)                                        # the transmission case
	_bx(a, Vector3(0.52, 0.58, 1.10), Vector3(0.0, 0.72, -1.30), blue)                                        # the engine
	_bx(a, Vector3(0.44, 0.60, 0.08), Vector3(0.0, 0.74, -1.88), grey)                                        # the radiator
	_bx(a, Vector3(0.40, 0.05, 1.10), Vector3(0.0, 1.03, -1.30), blue.darkened(0.15))                         # the hood
	_bx(a, Vector3(0.14, 0.50, 0.16), Vector3(0.0, 0.85, 0.12), grey)                                         # the seat post
	_bx(a, Vector3(0.40, 0.06, 0.34), Vector3(0.0, 1.07, 0.14), grey)                                         # the pan seat
	for rx in [-0.64, 0.64]:
		_wheel(a, Vector3(rx, 0.56, 0.14), 0.56, 0.24, orange, grey)                                         # the big rear wheels
		_wheel(a, Vector3(rx * 1.02, 0.56, 0.14), 0.585, 0.17, orange.darkened(0.35), grey)                  # their lugs, a darker band
		_bx(a, Vector3(0.26, 0.04, 0.80), Vector3(rx * 0.94, 1.14, 0.14), blue)                              # the mudguards
	for fx in [-0.46, 0.46]:
		_wheel(a, Vector3(fx, 0.30, -1.72), 0.30, 0.10, orange, grey)                                        # the small front wheels
	_bx(a, Vector3(1.0, 0.08, 0.08), Vector3(0.0, 0.30, -1.72), grey)                                         # the front axle
	_seg(a, Vector3(0.0, 0.90, -0.85), Vector3(0.0, 1.22, -0.50), 0.02, 0.02, grey)                           # the steering column
	AirfieldPeople._part(a, _flat_disc(0.19), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0.0, 1.26, -0.46)), black, 0, 0, false)
	_seg(a, Vector3(0.13, 1.03, -1.55), Vector3(0.13, 1.60, -1.55), 0.035, 0.03, black)                       # the exhaust pipe
	_bx(a, Vector3(0.5, 0.05, 0.45), Vector3(0.0, 0.62, -0.50), grey)                                         # the footboard
	# the trailed plough on the drawbar: a beam, two shares with their mouldboards, a land wheel at the back
	_seg(a, Vector3(0.0, 0.50, 0.55), Vector3(0.0, 0.46, 3.30), 0.04, 0.04, grey)
	for pz in [1.65, 2.55]:
		_bx(a, Vector3(0.28, 0.08, 0.55), Vector3(0.0, 0.06, pz), grey)
		_bx(a, Vector3(0.05, 0.34, 0.65), Vector3(0.20, 0.24, pz), grey, Basis(Vector3.BACK, -0.45))
		_bx(a, Vector3(0.05, 0.40, 0.06), Vector3(0.0, 0.26, pz - 0.2), grey)
	_wheel(a, Vector3(0.0, 0.20, 3.10), 0.20, 0.05, grey, grey)
	return _finish(a)


static func _flat_disc(r: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.025
	cm.radial_segments = 10
	cm.rings = 1
	return cm


static func _finish(a: AirfieldPeople._Acc) -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a.v
	arr[Mesh.ARRAY_NORMAL] = a.n
	arr[Mesh.ARRAY_COLOR] = a.c
	arr[Mesh.ARRAY_TEX_UV] = a.uv
	arr[Mesh.ARRAY_INDEX] = a.i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## The mesh of a prop type, built once.
static func prop_mesh(prop: int) -> ArrayMesh:
	if _prop_meshes.has(prop):
		return _prop_meshes[prop]
	var m: ArrayMesh
	match prop:
		Prop.HORSE_LED:
			m = _led_mesh(false)
		Prop.CART_LED:
			m = _led_mesh(true)
		Prop.CART_DRIVEN:
			m = _driven_mesh()
		Prop.PLOUGH_TEAM:
			m = _plough_mesh()
		_:
			m = _tractor_mesh()
	_prop_meshes[prop] = m
	return m


## The still things (a StandardMaterial3D on vertex colours): a stook is a tent of six sheaves, a haycock a squat cone, a
## haystack a pitched rick.
static func still_mesh(kind: int) -> ArrayMesh:
	if _still_meshes.has(kind):
		return _still_meshes[kind]
	var a := AirfieldPeople._Acc.new()
	var wheat := Color(0.72, 0.60, 0.27)
	var straw := Color(0.62, 0.52, 0.24)
	match kind:
		Still.STOOK:
			for i in 5:
				var ang: float = TAU * float(i) / 5.0
				var base := Vector3(cos(ang) * 0.30, 0.0, sin(ang) * 0.30)
				var top := Vector3(cos(ang) * 0.06, 0.95, sin(ang) * 0.06)
				_seg(a, base, top, 0.11, 0.035, wheat if i % 2 == 0 else straw)
			_seg(a, Vector3(0.0, 0.55, 0.0), Vector3(0.0, 1.12, 0.0), 0.15, 0.04, wheat.lightened(0.08))
		Still.HAYCOCK:
			_seg(a, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.35, 0.0), 0.95, 0.06, Color(0.58, 0.55, 0.26))
			_ell(a, Vector3(0.0, 0.42, 0.0), Vector3(0.80, 0.50, 0.80), Color(0.62, 0.58, 0.28))
		_:
			_bx(a, Vector3(2.9, 1.7, 5.0), Vector3(0.0, 0.85, 0.0), straw)
			_bx(a, Vector3(2.1, 2.1, 5.0), Vector3(0.0, 1.75, 0.0), straw.darkened(0.12), Basis(Vector3.BACK, PI * 0.25))
	var m: ArrayMesh = _finish(a)
	_still_meshes[kind] = m
	return m


# ------------------------------------------------------------------ spawning (main thread)

static func _prop_material(prop: int) -> ShaderMaterial:
	if _prop_mats.has(prop):
		return _prop_mats[prop]
	if _prop_shader == null:
		_prop_shader = load("res://shaders/farm_props.gdshader")
	var sm := ShaderMaterial.new()
	sm.shader = _prop_shader
	match prop:
		Prop.HORSE_LED, Prop.CART_LED:
			sm.set_shader_parameter("hz0", 0.70)
		Prop.CART_DRIVEN:
			sm.set_shader_parameter("hz0", -2.75)
		Prop.PLOUGH_TEAM:
			sm.set_shader_parameter("hz0", -5.0)
			sm.set_shader_parameter("hz1", -5.0)
	_prop_mats[prop] = sm
	return sm


static func _still_material() -> StandardMaterial3D:
	if _still_mat == null:
		_still_mat = StandardMaterial3D.new()
		_still_mat.vertex_color_use_as_albedo = true
		_still_mat.roughness = 1.0
		_still_mat.cull_mode = BaseMaterial3D.CULL_BACK
	return _still_mat


## Put a planned tile's farm life into the scene: one MultiMesh of figures (AirfieldPeople.spawn: the same Driver, so
## the folk throw themselves flat under enemy aircraft), one small MultiMesh per prop type and one per still thing.
## `center` is where the MultiMeshes sit (instance positions are stored relative to it).
static func spawn(container: Node3D, pl: Dictionary, center: Vector3, team: String, seed_v: int, label: String = "") -> void:
	var men: Array = pl.get("men", [])
	if men.is_empty() and (pl.get("still", {}) as Dictionary).is_empty():
		return
	var origin := Vector3(center.x, 0.0, center.z)
	var range_end: float = AirfieldPeople.TOWN_VIEW * minf(Scatter.vis_scale, 1.0)
	if not men.is_empty():
		var mi: MultiMeshInstance3D = AirfieldPeople.spawn(container, men, origin, team, seed_v, "", true)
		if mi != null:
			mi.name = "FarmPeople"
			mi.visibility_range_end = range_end
			mi.visibility_range_end_margin = 120.0
	var props: Dictionary = pl.get("props", {})
	for pk in props.keys():
		_spawn_props(container, int(pk), props[pk] as Array, origin, range_end)
	var stills: Dictionary = pl.get("still", {})
	for sk in stills.keys():
		_spawn_still(container, int(sk), stills[sk] as Array, origin, range_end)
	if label != "":
		print("[farm] %s: %d people, %d props, %d still" % [label, men.size(), _count(props), _count(stills)])
	_debug_farm_shot(pl, label)


static func _count(d: Dictionary) -> int:
	var n: int = 0
	for k in d.keys():
		n += (d[k] as Array).size()
	return n


## One MultiMesh of a prop type. The transform and beat of each instance are computed exactly as AirfieldPeople.spawn does
## for the man at its origin (a slope-following direction, beat length in mesh metres), so man and prop move as one.
static func _spawn_props(container: Node3D, prop: int, list: Array, origin: Vector3, range_end: float) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = prop_mesh(prop)
	mm.instance_count = list.size()
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for i in list.size():
		var e: Array = list[i]
		var w0: Vector3 = e[0]
		var dir: Vector3 = e[1]
		var ln: float = float(e[2])
		var p := Vector3(w0.x - origin.x, float(e[5]) + 0.01 - origin.y, w0.z - origin.z)
		var p1 := Vector3(p.x + dir.x * ln, float(e[6]) + 0.01 - origin.y, p.z + dir.z * ln)
		var d: Vector3 = dir
		if ln > 1.0:
			d = (p1 - p).normalized()
		var bas: Basis = Basis.looking_at(d, Vector3.UP).scaled(Vector3.ONE * AirfieldPeople.MAN)
		mm.set_instance_transform(i, Transform3D(bas, p))
		mm.set_instance_custom_data(i, Color(p.distance_to(p1) / AirfieldPeople.MAN, float(e[4]), float(e[3]), float(e[7])))
		for q in [p, p1]:
			lo = Vector3(minf(lo.x, (q as Vector3).x), minf(lo.y, (q as Vector3).y), minf(lo.z, (q as Vector3).z))
			hi = Vector3(maxf(hi.x, (q as Vector3).x), maxf(hi.y, (q as Vector3).y), maxf(hi.z, (q as Vector3).z))
	mm.custom_aabb = AABB(lo - Vector3(10.0, 2.0, 10.0), hi - lo + Vector3(20.0, 8.0, 20.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "FarmProps%d" % prop
	mi.multimesh = mm
	mi.material_override = _prop_material(prop)
	mi.position = origin
	mi.visibility_range_end = range_end
	mi.visibility_range_end_margin = 120.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	container.add_child(mi)


static func _spawn_still(container: Node3D, kind: int, list: Array, origin: Vector3, range_end: float) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = still_mesh(kind)
	mm.instance_count = list.size()
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for i in list.size():
		var e: Array = list[i]
		var wp: Vector3 = e[0]
		var p := Vector3(wp.x - origin.x, wp.y - 0.02 - origin.y, wp.z - origin.z)
		var bas: Basis = Basis(Vector3.UP, float(e[1])).scaled(Vector3.ONE * float(e[2]))
		mm.set_instance_transform(i, Transform3D(bas, p))
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	mm.custom_aabb = AABB(lo - Vector3(6.0, 1.0, 6.0), hi - lo + Vector3(12.0, 6.0, 12.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "FarmStill%d" % kind
	mi.multimesh = mm
	mi.material_override = _still_material()
	mi.position = origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = range_end * 0.8
	mi.visibility_range_end_margin = 80.0
	container.add_child(mi)


## Debug (--farm-shot[=<job>[,<distance>[,<lat>,<lon>]]]): a camera on a work party (hidden-desktop screenshots of the
## field work close up). <job> is plough, tractor, sow, hay, harvest, feed or any; with <lat>,<lon> only a party within
## 1.5 km of that point is taken (the tiles stream in around the player in no particular order).
static func _debug_farm_shot(pl: Dictionary, label: String) -> void:
	if _shot_made:
		return
	var arg: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--farm-shot") and a != "--farm-shot-short":
			arg = a
	if arg == "":
		return
	var rest: String = arg.substr(11)
	if rest.begins_with("="):
		rest = rest.substr(1)
	var parts: PackedStringArray = rest.split(",")
	var want: String = String(parts[0]).strip_edges() if parts.size() > 0 else "any"
	var back: float = 22.0
	if parts.size() > 1 and String(parts[1]).is_valid_float():
		back = float(parts[1])
	var near: Variant = null
	if parts.size() > 3 and String(parts[2]).is_valid_float() and String(parts[3]).is_valid_float():
		near = WorldCoords.latlon_to_world(float(parts[2]), float(parts[3]))
	var names: Array = ["plough", "tractor", "sow", "hay", "harvest", "feed"]
	var best: Dictionary = {}
	var best_d: float = 1.0e12
	for g in (pl.get("groups", []) as Array):
		var gd: Dictionary = g
		if want != "any" and want != "" and want != str(names[int(gd["job"])]):
			continue
		var gp: Vector3 = gd["pos"]
		var dd: float = 0.0
		if near != null:
			dd = Vector2(gp.x - (near as Vector3).x, gp.z - (near as Vector3).z).length()
			if dd > 1500.0:
				continue
		if dd < best_d:
			best_d = dd
			best = gd
	if best.is_empty():
		return
	var tp: Vector3 = best["pos"]
	var dv: Vector3 = best["dir"]
	var look: Vector3 = tp + Vector3(0.0, 1.0, 0.0)
	var side := Vector3(-dv.z, 0.0, dv.x)
	# the camera stands on whichever of the four sides has the lowest ground (never behind the hill beside the field)
	var cp: Vector3 = look
	var lowest: float = 1.0e9
	for sgn in [1.0, -1.0]:
		for fwd in [0.3, -0.3]:
			var cand: Vector3 = look + side * back * 0.8 * sgn - dv * back * fwd
			var gh: float = GroundKit.ground_y(cand.x, cand.z)
			if gh < lowest:
				lowest = gh
				cp = Vector3(cand.x, 0.0, cand.z)
	cp.y = maxf(tp.y + back * 0.25, lowest + 2.5)
	var cam := AirfieldPeople.TownShot.new()
	cam.fov = 50.0
	cam.transform = Transform3D(Basis.looking_at(look - cp, Vector3.UP), cp)
	cam.hold_s = 900.0
	GroundKit.tree().root.add_child.call_deferred(cam)
	_shot_made = true
	print("[farm-shot] %s job %s at %.0f, %.0f (%.0f m back, %d people, %.0f m from the --near point %s)" % [label, names[int(best["job"])], tp.x, tp.z, back, int(best["men"]), best_d, str(near)])
