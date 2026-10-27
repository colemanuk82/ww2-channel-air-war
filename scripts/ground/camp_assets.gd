class_name CampAssets
extends RefCounted
## Meshes for army camps and prisoner-of-war / labour camps: wire fences, concertina, guard towers, gates, timber
## barrack huts, cookhouses, water towers, sandbagged ammunition bays, fuel-drum dumps and disruptive-painted tents.
## Built from the photographs and the surviving model of Stalag Luft III (Zagan museum): long tar-roofed timber huts
## raised on blocks, double 2.5 m wire fences with coiled concertina between, "goon box" towers on four legs at the
## corners and along the wire, a gatehouse and vorlager; and from the 1944 marshalling-area photographs of the
## invasion camps (tents painted in disruptive patterns, vehicles under nets, ammunition stacked in sandbag bays).
##
## All centred on the origin with base y = 0; long axis along Z unless noted. Cached in Scatter._meshes.

const WOOD := Color(0.36, 0.28, 0.19)
const WOOD_PALE := Color(0.52, 0.44, 0.31)
const TAR := Color(0.25, 0.25, 0.24)
const WIRE := Color(0.30, 0.27, 0.23)
const SANDBAG := Color(0.45, 0.40, 0.29)
const DARK := Color(0.07, 0.07, 0.06)


## The camp meshes, built behind the loading screen (main.gd) so the first camp flown over does not build them.
static func warm_jobs() -> Array:
	var out: Array = [Callable(CampAssets, "fence_bay").bind(false), Callable(CampAssets, "fence_bay").bind(true),
		Callable(CampAssets, "concertina"), Callable(CampAssets, "cookhouse"), Callable(CampAssets, "water_tower"),
		Callable(CampAssets, "slit_trench"), Callable(CampAssets, "goalposts")]
	for st in ["pow", "army"]:
		out.append(Callable(CampAssets, "guard_tower").bind(st))
	for st2 in ["stalag", "ot"]:
		out.append(Callable(CampAssets, "barrack_hut").bind(st2))
	for team in ["Allies", "Axis"]:
		for f in ["gate", "ammo_bay", "drum_dump"]:
			out.append(Callable(CampAssets, f).bind(team))
		for v in 2:
			out.append(Callable(CampAssets, "camo_tent").bind(team, v))
	return out


static func _cget(key: String) -> ArrayMesh:
	return Scatter._meshes[key] if Scatter._meshes.has(key) else null


static func _keep(key: String, parts: Array) -> ArrayMesh:
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m


## One 5 m bay of wire fence running along +X from the origin: a timber post and four strands. With `overhang`
## the post carries the inward-cranked arm of a POW fence with two more strands.
static func fence_bay(overhang: bool) -> ArrayMesh:
	var key: String = "fence_bay_%s" % str(overhang)
	if _cget(key) != null:
		return _cget(key)
	var parts: Array = []
	var h: float = 2.6 if overhang else 1.8
	parts.append(GroundKit.box_part(Vector3(0.16, h + 0.4, 0.16), Vector3(0, h * 0.5 - 0.2, 0), WOOD, Vector3.ZERO, false))
	var n: int = 6 if overhang else 4
	for i in n:
		var y: float = 0.35 + float(i) * (h - 0.4) / float(n - 1)
		parts.append(GroundKit.box_part(Vector3(5.0, 0.05, 0.05), Vector3(2.5, y, 0), WIRE, Vector3.ZERO, false))
	if overhang:
		parts.append(GroundKit.box_part(Vector3(0.1, 0.9, 0.1), Vector3(0, h + 0.3, 0.32), WOOD, Vector3(45, 0, 0), false))
		for k in 2:
			parts.append(GroundKit.box_part(Vector3(5.0, 0.05, 0.05), Vector3(2.5, h + 0.2 + float(k) * 0.3, 0.25 + float(k) * 0.3), WIRE, Vector3.ZERO, false))
	return _keep(key, parts)


## A 5 m roll of concertina wire along +X (laid between the two POW fences and round army-camp dumps).
static func concertina() -> ArrayMesh:
	if _cget("concertina") != null:
		return _cget("concertina")
	var parts: Array = []
	for i in 6:
		parts.append(GroundKit.cyl_part(0.5, 0.5, 0.06, Vector3(0.4 + float(i) * 0.84, 0.5, 0), WIRE, Vector3(0, 0, 90), 8, false))
	parts.append(GroundKit.cyl_part(0.3, 0.3, 5.0, Vector3(2.5, 0.45, 0), WIRE.lightened(0.1), Vector3(0, 0, 90), 6, false))
	return _keep("concertina", parts)


## Guard tower. "pow": a 6 m timber "goon box" on four splayed legs with a roofed cab and searchlight.
## "army": a lower sandbag-skirted sentry platform with a corrugated roof.
static func guard_tower(style: String) -> ArrayMesh:
	var key: String = "guard_tower_" + style
	if _cget(key) != null:
		return _cget(key)
	var parts: Array = []
	var h: float = 6.2 if style == "pow" else 4.2
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.22, h + 0.3, 0.22), Vector3(sx * 1.25, h * 0.5, sz * 1.25), WOOD, Vector3(-sz * 3.0, 0, sx * 3.0), false))
	for k in 2:   # cross-bracing on two faces
		var y: float = h * (0.3 + 0.35 * float(k))
		parts.append(GroundKit.box_part(Vector3(2.8, 0.12, 0.12), Vector3(0, y, 1.3), WOOD, Vector3(0, 0, 32.0 * (1.0 if k == 0 else -1.0)), false))
		parts.append(GroundKit.box_part(Vector3(0.12, 0.12, 2.8), Vector3(1.3, y, 0), WOOD, Vector3(32.0 * (1.0 if k == 0 else -1.0), 0, 0), false))
	parts.append(GroundKit.box_part(Vector3(3.2, 0.2, 3.2), Vector3(0, h, 0), WOOD_PALE))                    # floor
	if style == "pow":
		for s in 4:   # half-height boarded walls, open above for the guard to look out
			var a: float = float(s) * 90.0
			var d: Vector3 = Basis(Vector3.UP, deg_to_rad(a)) * Vector3(0, 0, 1.55)
			parts.append(GroundKit.box_part(Vector3(3.2, 1.15, 0.1), Vector3(d.x, h + 0.65, d.z), WOOD_PALE, Vector3(0, a, 0)))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				parts.append(GroundKit.box_part(Vector3(0.12, 1.2, 0.12), Vector3(sx * 1.5, h + 1.8, sz * 1.5), WOOD, Vector3.ZERO, false))
		var roof := GroundKit.prism_mesh(4.0, 4.0, 1.1)
		parts.append([roof, Transform3D(Basis.IDENTITY, Vector3(0, h + 2.4, 0)), GroundKit.mat(TAR)])
		parts.append(GroundKit.cyl_part(0.28, 0.24, 0.5, Vector3(1.2, h + 1.55, -1.3), Color(0.25, 0.26, 0.27), Vector3(80, 0, 0), 8, false))   # searchlight
		parts.append(GroundKit.box_part(Vector3(0.5, 0.08, 4.0), Vector3(-1.4, h * 0.5, 2.6), WOOD, Vector3(-42, 0, 0), false))     # ladder
	else:
		for s in 4:
			var a2: float = float(s) * 90.0
			var d2: Vector3 = Basis(Vector3.UP, deg_to_rad(a2)) * Vector3(0, 0, 1.5)
			parts.append(GroundKit.box_part(Vector3(3.2, 1.0, 0.45), Vector3(d2.x, h + 0.55, d2.z), SANDBAG, Vector3(0, a2, 0)))
		for sx in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.12, 1.6, 0.12), Vector3(sx * 1.4, h + 1.6, 1.4), WOOD, Vector3.ZERO, false))
			parts.append(GroundKit.box_part(Vector3(0.12, 1.3, 0.12), Vector3(sx * 1.4, h + 1.45, -1.4), WOOD, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(3.6, 0.1, 3.6), Vector3(0, h + 2.3, 0), Color(0.36, 0.37, 0.32), Vector3(8, 0, 0)))
	return _keep(key, parts)


## Gateway: two tall posts, a red-and-white barrier pole and a sentry box. Opening 8 m wide across X.
static func gate(team: String) -> ArrayMesh:
	var key: String = "camp_gate_" + team
	if _cget(key) != null:
		return _cget(key)
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(0.35, 3.4, 0.35), Vector3(sx * 4.2, 1.7, 0), WOOD))
	for i in 8:
		var c: Color = Color(0.72, 0.12, 0.10) if i % 2 == 0 else Color(0.90, 0.88, 0.82)
		if team == "Axis":
			c = Color(0.72, 0.12, 0.10) if i % 2 == 0 else Color(0.92, 0.92, 0.90)
		parts.append(GroundKit.box_part(Vector3(1.0, 0.16, 0.16), Vector3(-3.5 + float(i) * 1.0, 1.05, 0), c, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.5, 1.1, 0.5), Vector3(-4.6, 0.55, 0.6), WOOD))
	# sentry box
	var paint: Color = Color(0.32, 0.33, 0.24) if team == "Allies" else Color(0.40, 0.40, 0.36)
	parts.append(GroundKit.box_part(Vector3(1.3, 2.3, 1.3), Vector3(5.6, 1.15, 1.2), paint))
	parts.append(GroundKit.box_part(Vector3(1.5, 0.14, 1.5), Vector3(5.6, 2.35, 1.2), TAR, Vector3(0, 0, 6), false))
	parts.append(GroundKit.box_part(Vector3(0.8, 1.7, 0.06), Vector3(5.6, 1.0, 0.54), DARK, Vector3.ZERO, false))
	return _keep(key, parts)


## Long timber barrack hut (POW / labour camp): 10 x 40 m on brick piers, tar-paper gable roof, three chimney
## stacks on the ridge, window row and end doors. `style` "ot" makes the rougher, unpainted labour-camp hut.
static func barrack_hut(style: String) -> ArrayMesh:
	var key: String = "barrack_hut_" + style
	if _cget(key) != null:
		return _cget(key)
	var parts: Array = []
	var wall: Color = WOOD_PALE if style != "ot" else Color(0.40, 0.34, 0.25)
	var L: float = 40.0 if style != "ot" else 30.0
	parts.append(GroundKit.box_part(Vector3(9.6, 0.6, L - 0.4), Vector3(0, 0.3, 0), Color(0.40, 0.30, 0.24), Vector3.ZERO, false))   # piers / skirt
	parts.append(GroundKit.box_part(Vector3(9.4, 2.5, L - 0.6), Vector3(0, 1.85, 0), wall))
	var roof := GroundKit.prism_mesh(10.6, L + 0.6, 2.4)
	parts.append([roof, Transform3D(Basis.IDENTITY, Vector3(0, 3.1, 0)), GroundKit.mat(TAR)])
	var nwin: int = int(L / 4.0)
	for i in nwin:
		var z: float = -L * 0.5 + 2.4 + float(i) * (L - 4.8) / float(nwin - 1)
		for sx in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.06, 0.9, 1.1), Vector3(sx * 4.72, 2.1, z), Color(0.12, 0.14, 0.15), Vector3.ZERO, false))
	for zs in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(1.2, 2.0, 0.06), Vector3(0, 1.6, zs * (L * 0.5 - 0.28)), DARK, Vector3.ZERO, false))
	for k in 3:
		parts.append(GroundKit.box_part(Vector3(0.6, 1.4, 0.6), Vector3(0, 5.2, -L * 0.3 + float(k) * L * 0.3), Color(0.42, 0.30, 0.24), Vector3.ZERO, false))
	return _keep(key, parts)


## Cookhouse / ablution block: a wider hut with a tall brick chimney.
static func cookhouse() -> ArrayMesh:
	if _cget("cookhouse") != null:
		return _cget("cookhouse")
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(13.4, 3.2, 26.0), Vector3(0, 1.6, 0), WOOD_PALE.darkened(0.08)))
	var roof := GroundKit.prism_mesh(14.6, 27.0, 3.0)
	parts.append([roof, Transform3D(Basis.IDENTITY, Vector3(0, 3.2, 0)), GroundKit.mat(TAR)])
	parts.append(GroundKit.box_part(Vector3(1.2, 9.5, 1.2), Vector3(3.5, 4.75, 8.0), Color(0.48, 0.30, 0.22)))
	for i in 5:
		parts.append(GroundKit.box_part(Vector3(0.06, 1.0, 1.6), Vector3(6.72, 2.0, -9.0 + float(i) * 4.5), Color(0.12, 0.14, 0.15), Vector3.ZERO, false))
	return _keep("cookhouse", parts)


## Water tower: a riveted tank on a 10 m timber trestle.
static func water_tower() -> ArrayMesh:
	if _cget("water_tower") != null:
		return _cget("water_tower")
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.3, 10.4, 0.3), Vector3(sx * 1.7, 5.2, sz * 1.7), WOOD, Vector3(-sz * 2.5, 0, sx * 2.5), false))
	for k in 3:
		parts.append(GroundKit.box_part(Vector3(3.8, 0.16, 0.16), Vector3(0, 2.5 + float(k) * 3.0, 1.75), WOOD, Vector3(0, 0, 30.0 * (1.0 - 2.0 * float(k % 2))), false))
		parts.append(GroundKit.box_part(Vector3(0.16, 0.16, 3.8), Vector3(1.75, 2.5 + float(k) * 3.0, 0), WOOD, Vector3(30.0 * (1.0 - 2.0 * float(k % 2)), 0, 0), false))
	parts.append(GroundKit.box_part(Vector3(4.6, 3.0, 4.6), Vector3(0, 11.8, 0), Color(0.33, 0.34, 0.33)))
	parts.append(GroundKit.box_part(Vector3(4.9, 0.2, 4.9), Vector3(0, 13.4, 0), TAR, Vector3.ZERO, false))
	return _keep("water_tower", parts)


## Sandbagged ammunition bay (open to +Z): a U of sandbag wall 1.5 m high round stacked boxes under a tarpaulin.
## About 9 x 7 m.
static func ammo_bay(team: String) -> ArrayMesh:
	var key: String = "ammo_bay_" + team
	if _cget(key) != null:
		return _cget(key)
	var parts: Array = []
	var crate: Color = Color(0.30, 0.33, 0.20) if team == "Allies" else Color(0.36, 0.36, 0.30)
	for row in 3:   # sandbag courses, alternating shade so the bags read
		var y: float = 0.25 + float(row) * 0.48
		var c: Color = SANDBAG if row % 2 == 0 else SANDBAG.darkened(0.1)
		parts.append(GroundKit.box_part(Vector3(9.0, 0.5, 1.0), Vector3(0, y, -3.0), c, Vector3.ZERO, row == 2))
		for sx in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(1.0, 0.5, 6.0), Vector3(sx * 4.0, y, 0.5), c, Vector3.ZERO, row == 2))
	for i in 3:
		for j in 2:
			parts.append(GroundKit.box_part(Vector3(1.8, 0.9 + 0.3 * float((i + j) % 2), 1.4), Vector3(-2.2 + float(i) * 2.2, 0.5, -1.4 + float(j) * 1.8), crate))
	parts.append(GroundKit.box_part(Vector3(7.2, 0.08, 4.4), Vector3(0, 1.45, -0.6), Color(0.28, 0.29, 0.20), Vector3(4, 0, 0), false))   # tarpaulin
	return _keep(key, parts)


## Fuel dump: a block of 200-litre drums standing on duckboards with stacks of jerrycans alongside. About 8 x 6 m.
static func drum_dump(team: String) -> ArrayMesh:
	var key: String = "drum_dump_" + team
	if _cget(key) != null:
		return _cget(key)
	var parts: Array = []
	var drum: Color = Color(0.25, 0.30, 0.20) if team == "Allies" else Color(0.32, 0.33, 0.30)
	var can: Color = Color(0.30, 0.33, 0.22) if team == "Allies" else Color(0.38, 0.38, 0.32)
	parts.append(GroundKit.box_part(Vector3(5.2, 0.12, 4.2), Vector3(-1.0, 0.06, 0), WOOD.darkened(0.1), Vector3.ZERO, false))
	for i in 7:
		for j in 6:
			var col: Color = drum if (i * 3 + j) % 5 != 0 else drum.darkened(0.2)
			parts.append(GroundKit.cyl_part(0.3, 0.3, 0.9, Vector3(-3.3 + float(i) * 0.7, 0.57, -1.75 + float(j) * 0.7), col, Vector3.ZERO, 7, false))
	for k in 3:   # jerrycan stacks
		parts.append(GroundKit.box_part(Vector3(1.6, 1.0 + 0.2 * float(k), 1.2), Vector3(2.8, 0.5 + 0.1 * float(k), -1.6 + float(k) * 1.6), can))
	return _keep(key, parts)


## Ridge tent painted in a disruptive pattern (variant 0/1 swap the patch layout).
static func camo_tent(team: String, v: int) -> ArrayMesh:
	var key: String = "camo_tent_%s_%d" % [team, v]
	if _cget(key) != null:
		return _cget(key)
	var base: Color = Color(0.43, 0.42, 0.30) if team == "Allies" else Color(0.41, 0.42, 0.35)
	var patch: Color = Color(0.25, 0.27, 0.17) if team == "Allies" else Color(0.30, 0.33, 0.22)
	var patch2: Color = Color(0.33, 0.27, 0.19)
	var parts: Array = []
	for sd in [-1.0, 1.0]:
		var rot := Vector3(0, 0, -sd * 50.2)
		parts.append(GroundKit.box_part(Vector3(3.12, 0.1, 6.0), Vector3(sd * 1.0, 1.2, 0), base, rot))
		for p in 3:
			var off: float = (-1.8 + float(p) * 1.8) * (1.0 if (v + p) % 2 == 0 else -0.7)
			var c: Color = patch if (p + v) % 2 == 0 else patch2
			var lift := Basis.from_euler(Vector3(0, 0, deg_to_rad(rot.z))) * Vector3(0, 0.07, 0)
			parts.append(GroundKit.box_part(Vector3(1.6 + 0.5 * float(p % 2), 0.04, 1.5 + 0.4 * float((p + v) % 2)), Vector3(sd * 1.0, 1.2, off) + lift + Vector3(sd * 0.25 * float(p % 2), 0.0, 0.0), c, rot, false))
	parts.append(GroundKit.box_part(Vector3(0.14, 0.14, 6.3), Vector3(0, 2.42, 0), base.darkened(0.3), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.1, 1.5, 0.1), Vector3(0, 0.8, 3.0), DARK, Vector3.ZERO, false))
	return _keep(key, parts)


## Earth-bank latrine / slit-trench line marker: a low raw-earth spoil bank. 12 x 1.6 m.
static func slit_trench() -> ArrayMesh:
	if _cget("slit_trench") != null:
		return _cget("slit_trench")
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(12.0, 0.5, 1.0), Vector3(0, 0.2, 0.9), Color(0.38, 0.31, 0.21), Vector3(0, 0, 0), false))
	parts.append(GroundKit.box_part(Vector3(11.6, 0.08, 0.8), Vector3(0, 0.02, 0), Color(0.12, 0.10, 0.08), Vector3.ZERO, false))
	return _keep("slit_trench", parts)


## Football / sports goalposts for the POW sports field (the camps' "Appellplatz" doubled as a pitch).
static func goalposts() -> ArrayMesh:
	if _cget("goalposts") != null:
		return _cget("goalposts")
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(0.14, 2.4, 0.14), Vector3(sx * 3.6, 1.2, 0), Color(0.86, 0.85, 0.80), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(7.4, 0.14, 0.14), Vector3(0, 2.4, 0), Color(0.86, 0.85, 0.80), Vector3.ZERO, false))
	return _keep("goalposts", parts)


# ------------------------------------------------------------------ placement helpers
## Fence bays (and optional concertina rolls) round a rectangle in camp-local space, x in [-hx, hx], z in [-hz, hz].
## gap_x: half-width of the gate gap on the +Z side (0 = none). Returns world transforms for the bay MultiMesh.
static func fence_ring(axf: Transform3D, yaw: float, hx: float, hz: float, gap_x: float) -> Array:
	var out: Array = []
	var corners: Array = [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for e in 4:
		var a: Vector3 = corners[e]
		var b: Vector3 = corners[(e + 1) % 4]
		var L: float = a.distance_to(b)
		var dir: Vector3 = (b - a) / L
		var n: int = int(ceil(L / 5.0))
		var bay_yaw: float = atan2(-dir.z, dir.x)
		for i in n:
			var lp: Vector3 = a + dir * (float(i) * 5.0)
			if gap_x > 0.0 and e == 2 and lp.x > -gap_x and lp.x - 5.0 < gap_x:
				continue   # gate gap (edge 2 runs from +x to -x along +Z)
			var p: Vector3 = axf * lp
			p.y = GroundKit.ground_y(p.x, p.z)
			var bl: float = minf(5.0, L - float(i) * 5.0) / 5.0
			out.append(Transform3D(Basis(Vector3.UP, yaw + bay_yaw) * Basis.from_scale(Vector3(bl, 1.0, 1.0)), p))
	return out


## Thin earth / gravel track segments from local a to b, following the ground (one MultiMesh of unit boxes).
static func track_xforms(axf: Transform3D, a: Vector3, b: Vector3, width: float) -> Array:
	var out: Array = []
	var L: float = a.distance_to(b)
	var n: int = maxi(1, int(ceil(L / 14.0)))
	for i in n:
		var p0: Vector3 = axf * a.lerp(b, float(i) / float(n))
		var p1: Vector3 = axf * a.lerp(b, float(i + 1) / float(n))
		p0.y = GroundKit.ground_y(p0.x, p0.z)
		p1.y = GroundKit.ground_y(p1.x, p1.z)
		var d: Vector3 = p1 - p0
		var seg: float = d.length() + 1.2
		var fwd: Vector3 = d.normalized()
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		var up: Vector3 = right.cross(fwd).normalized()
		var basis := Basis(right * width, up * 0.14, -fwd * seg)
		out.append(Transform3D(basis, (p0 + p1) * 0.5 + Vector3(0, 0.05, 0)))
	return out


## Trees scattered through a camp, avoiding the given local rectangles [[centre Vector3, half-size Vector2], ...].
## Returns [cone transforms, round transforms].
static func tree_xforms(axf: Transform3D, rng: RandomNumberGenerator, hx: float, hz: float, n: int, avoid: Array) -> Array:
	var cones: Array = []
	var rounds: Array = []
	var tries: int = 0
	while cones.size() + rounds.size() < n and tries < n * 12:
		tries += 1
		var lp := Vector3(rng.randf_range(-hx, hx), 0.0, rng.randf_range(-hz, hz))
		var ok: bool = true
		for r in avoid:
			var c: Vector3 = r[0]
			var h: Vector2 = r[1]
			if absf(lp.x - c.x) < h.x + 4.0 and absf(lp.z - c.z) < h.y + 4.0:
				ok = false
				break
		if not ok:
			continue
		var p: Vector3 = axf * lp
		if GroundKit.raw_y(p.x, p.z) < 1.0:
			continue
		var sc: float = rng.randf_range(0.8, 1.25)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.25), sc)), Vector3(p.x, GroundKit.ground_y(p.x, p.z) - 0.3, p.z))
		if rng.randf() < 0.35:
			cones.append(t)
		else:
			rounds.append(t)
	return [cones, rounds]


static func add_trees(container: Node3D, trees: Array) -> void:
	if not (trees[0] as Array).is_empty():
		container.add_child(Scatter.multi(Scatter.tree_mesh(false), trees[0], 7000.0))
	if not (trees[1] as Array).is_empty():
		container.add_child(Scatter.multi(Scatter.tree_mesh(true), trees[1], 7000.0))
