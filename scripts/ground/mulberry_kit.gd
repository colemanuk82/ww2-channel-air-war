class_name MulberryKit
extends RefCounted
## The Mulberry artificial harbours, June 1944 onwards, built from the Admiralty and IWM aerial photographs of
## "Port Winston" at Arromanches (Mulberry B) and of Mulberry A off Saint-Laurent / Omaha.
##
## Mulberry B: an arc of Phoenix caissons (reinforced-concrete boxes up to 62 x 17 x 18 m, a few metres showing above
## the water, some carrying a Bofors platform) from Tracy-sur-Mer round to Asnelles, closed at the west by the line of
## Gooseberry blockships; inside it three Whale floating roadways on their pontoons ("beetles") running out from the
## beach to the Spud pierheads (pontoons with four tall legs standing on the seabed); a line of cross-shaped Bombardon
## floats anchored outside.
##
## Dates (Wikipedia, Mulberry harbour): first Phoenix sunk on 8 June 1944, the arc complete by 15 June; piers working
## from about 14 June; in use for about ten months. Mulberry A was wrecked by the storm of 19-22 June 1944 (21 of its
## 28 Phoenixes destroyed, the roadways smashed) and abandoned; its broken caissons and blockships stayed. The
## Bombardons broke loose in the same storm. The caissons at Arromanches are still there, so they never go away.
##
## Cost: per harbour one MultiMesh per part (caissons, gun platforms, roadway spans, pontoons, pierheads, spud legs,
## bombardons); fades at 20 km (caissons, a navigation landmark from altitude) and 6 km (the roadway detail).

const PHOENIX_LEN := 60.0
const VIS_FAR := 20000.0
const VIS_NEAR := 6000.0

## Harbour layouts in lat/lon. The arc control points follow the 1944 aerial photographs of each harbour.
const HARBOURS := {
	"B": {
		"arc": [[49.3434, -0.6520], [49.3500, -0.6460], [49.3555, -0.6330], [49.3570, -0.6180], [49.3555, -0.6020], [49.3510, -0.5900], [49.3460, -0.5840]],
		"blockships": [[49.3436, -0.6560], [49.3438, -0.6610], [49.3441, -0.6660]],
		"piers": [[[49.3392, -0.6250], [49.3490, -0.6230]], [[49.3394, -0.6195], [49.3500, -0.6150]], [[49.3398, -0.6140], [49.3480, -0.6060]]],
		"bombardon": [[49.3640, -0.6400], [49.3660, -0.6000]],
		"from": "1944-06-08", "complete": "1944-06-15", "piers_from": "1944-06-14", "piers_to": "1945-03-31", "storm": "",
	},
	"A": {
		"arc": [[49.3700, -0.8980], [49.3760, -0.8900], [49.3790, -0.8780], [49.3780, -0.8650], [49.3740, -0.8560]],
		"blockships": [[49.3690, -0.9020], [49.3685, -0.9070], [49.3735, -0.8520]],
		"piers": [[[49.3660, -0.8800], [49.3740, -0.8780]], [[49.3655, -0.8730], [49.3735, -0.8700]]],
		"bombardon": [[49.3880, -0.8950], [49.3890, -0.8600]],
		"from": "1944-06-08", "complete": "1944-06-16", "piers_from": "1944-06-16", "piers_to": "1944-06-19", "storm": "1944-06-20",
	},
}


static func world(ll: Array) -> Vector3:
	return WorldCoords.latlon_to_world(float(ll[0]), float(ll[1]))


## True when anything of this harbour exists on the current war date.
static func active(id: String) -> bool:
	return EraClock.is_between(str(HARBOURS[id]["from"]), "")


static func centre(id: String) -> Vector3:
	var arc: Array = HARBOURS[id]["arc"]
	return world(arc[arc.size() / 2])


static func build(id: String) -> Node3D:
	var h: Dictionary = HARBOURS[id]
	var root := Node3D.new()
	root.name = "Mulberry_" + id
	if not active(id):
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mulberry_" + id)
	var wrecked: bool = str(h["storm"]) != "" and EraClock.current() >= str(h["storm"])
	var built: float = EraClock.ramp(str(h["from"]), str(h["complete"]))
	# --- Phoenix caissons along the arc
	var pts: Array = []
	for p in (h["arc"] as Array):
		pts.append(world(p))
	var caissons: Array = []
	var guns: Array = []
	var broken: Array = []
	var along: float = 0.0
	var total: float = 0.0
	for i in pts.size() - 1:
		total += (pts[i] as Vector3).distance_to(pts[i + 1])
	var n_total: int = int(total / (PHOENIX_LEN + 4.0))
	var n_built: int = maxi(1, int(float(n_total) * maxf(built, 0.08)))
	var k: int = 0
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg: float = a.distance_to(b)
		var dir: Vector3 = (b - a) / seg
		var yaw: float = atan2(-dir.z, dir.x)
		var t: float = fposmod(-along, PHOENIX_LEN + 4.0)
		while t < seg:
			if k < n_built:
				var p: Vector3 = a + dir * (t + PHOENIX_LEN * 0.5)
				p.y = 0.0
				var jitter: float = rng.randf_range(-0.03, 0.03)
				if wrecked and rng.randf() < 0.75:
					# storm-wrecked: broken, tilted, settled low, some swung across the line
					var tilt := Basis(Vector3.UP, yaw + jitter + rng.randf_range(-0.6, 0.6)) * Basis(Vector3.FORWARD, rng.randf_range(-0.35, 0.35))
					broken.append(Transform3D(tilt, p + Vector3(rng.randf_range(-25, 25), rng.randf_range(-3.5, -1.5), rng.randf_range(-25, 25))))
				else:
					caissons.append(Transform3D(Basis(Vector3.UP, yaw + jitter), p))
					if k % 7 == 3:
						guns.append(Transform3D(Basis(Vector3.UP, yaw + jitter), p))
			k += 1
			t += PHOENIX_LEN + 4.0
		along += seg
	if not caissons.is_empty():
		root.add_child(Scatter.multi(phoenix_mesh(), caissons, VIS_FAR))
	if not broken.is_empty():
		root.add_child(Scatter.multi(phoenix_mesh(), broken, VIS_FAR))
	if not guns.is_empty():
		root.add_child(Scatter.multi(bofors_platform_mesh(), guns, VIS_NEAR))
	# --- Gooseberry blockships at the open end (these stay after the storm)
	var ships: Array = []
	for bp in (h["blockships"] as Array):
		var c: Vector3 = world(bp)
		for j in 3:
			ships.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25) + PI * 0.5), c + Vector3(float(j) * 140.0 - 140.0, -2.5, rng.randf_range(-20, 20))))
	root.add_child(Scatter.multi(blockship_mesh(), ships, VIS_FAR))
	# --- Whale roadways and Spud pierheads
	var piers_on: bool = EraClock.is_between(str(h["piers_from"]), str(h["piers_to"]))
	var piers_wreck: bool = wrecked
	if piers_on or piers_wreck:
		var spans: Array = []
		var beetles: Array = []
		var heads: Array = []
		var legs: Array = []
		for pr in (h["piers"] as Array):
			var s0: Vector3 = world(pr[0])
			var s1: Vector3 = world(pr[1])
			var L: float = s0.distance_to(s1)
			var pd: Vector3 = (s1 - s0) / L
			var pyaw: float = atan2(-pd.z, pd.x)
			var n: int = int(L / 24.0)
			for i in n:
				if piers_wreck and rng.randf() < 0.55:
					continue
				var pp: Vector3 = s0 + pd * (float(i) * 24.0 + 12.0)
				var off := Vector3.ZERO
				var tw := Basis(Vector3.UP, pyaw)
				if piers_wreck:
					off = Vector3(rng.randf_range(-15, 15), rng.randf_range(-1.2, -0.3), rng.randf_range(-15, 15))
					tw = Basis(Vector3.UP, pyaw + rng.randf_range(-0.7, 0.7)) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
				spans.append(Transform3D(tw, Vector3(pp.x, 1.6, pp.z) + off))
				beetles.append(Transform3D(tw, Vector3(pp.x + pd.x * 12.0, 0.0, pp.z + pd.z * 12.0) + off))
			if not piers_wreck:
				var hp: Vector3 = s1 + pd * 30.0
				heads.append(Transform3D(Basis(Vector3.UP, pyaw + PI * 0.5), Vector3(hp.x, 0.0, hp.z)))
				for lx in [-1.0, 1.0]:
					for lz in [-1.0, 1.0]:
						var side := Vector3(-pd.z, 0.0, pd.x)
						var lp: Vector3 = hp + pd * (lz * 27.0) + side * (lx * 7.0)
						legs.append(Transform3D(Basis.IDENTITY, Vector3(lp.x, 8.0, lp.z)))
		if not spans.is_empty():
			root.add_child(Scatter.multi(whale_span_mesh(), spans, VIS_NEAR))
			root.add_child(Scatter.multi(beetle_mesh(), beetles, VIS_NEAR))
		if not heads.is_empty():
			root.add_child(Scatter.multi(pierhead_mesh(), heads, VIS_FAR * 0.5))
			root.add_child(Scatter.multi(spud_leg_mesh(), legs, VIS_FAR * 0.5))
	# --- Bombardons (6 June until the storm)
	if EraClock.is_between("1944-06-06", "1944-06-19"):
		var b0: Vector3 = world(h["bombardon"][0])
		var b1: Vector3 = world(h["bombardon"][1])
		var bombs: Array = []
		for i in 24:
			var bp2: Vector3 = b0.lerp(b1, (float(i) + 0.5) / 24.0)
			bombs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), Vector3(bp2.x, 0.0, bp2.z)))
		root.add_child(Scatter.multi(bombardon_mesh(), bombs, VIS_NEAR))
	return root


# ------------------------------------------------------------------ meshes (water line at y = 0)
static func _keep(key: String, parts: Array) -> ArrayMesh:
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes[key] = m
	return m


## Phoenix caisson, type A1-like: 60 x 17 m, 4.5 m showing above the waterline, open-topped cellular box with
## cross-walls, a darker weed/tide band at the waterline. Long axis along X.
static func phoenix_mesh() -> ArrayMesh:
	if Scatter._meshes.has("phoenix"):
		return Scatter._meshes["phoenix"]
	var conc := Color(0.62, 0.61, 0.57)
	var tide := Color(0.27, 0.29, 0.25)
	var inner := Color(0.20, 0.21, 0.20)
	var parts: Array = []
	for sz in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(PHOENIX_LEN, 4.5, 0.8), Vector3(0, 2.25, sz * 8.1), conc))
		parts.append(GroundKit.box_part(Vector3(PHOENIX_LEN + 0.2, 1.2, 0.9), Vector3(0, 0.4, sz * 8.1), tide, Vector3.ZERO, false))
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(0.8, 4.5, 16.2), Vector3(sx * (PHOENIX_LEN * 0.5 - 0.4), 2.25, 0), conc))
	for i in 5:
		parts.append(GroundKit.box_part(Vector3(0.4, 4.0, 15.4), Vector3(-PHOENIX_LEN * 0.5 + 10.0 * float(i + 1), 2.0, 0), conc.darkened(0.1), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(PHOENIX_LEN - 1.6, 0.2, 15.4), Vector3(0, 1.4, 0), inner, Vector3.ZERO, false))   # water inside the cells
	return _keep("phoenix", parts)


## Bofors platform carried on some Phoenixes: a raised steel deck, sandbags, the gun. Sits on the caisson's top.
static func bofors_platform_mesh() -> ArrayMesh:
	if Scatter._meshes.has("phoenix_bofors"):
		return Scatter._meshes["phoenix_bofors"]
	var steel := Color(0.35, 0.37, 0.36)
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(GroundKit.box_part(Vector3(0.3, 3.5, 0.3), Vector3(sx * 2.8, 6.2, sz * 2.8), steel, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(6.6, 0.3, 6.6), Vector3(0, 8.0, 0), steel))
	parts.append(GroundKit.box_part(Vector3(6.6, 0.9, 0.5), Vector3(0, 8.6, 3.1), Color(0.5, 0.45, 0.33), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(6.6, 0.9, 0.5), Vector3(0, 8.6, -3.1), Color(0.5, 0.45, 0.33), Vector3.ZERO, false))
	parts.append(GroundKit.cyl_part(0.9, 1.1, 1.0, Vector3(0, 8.7, 0), Color(0.28, 0.31, 0.24), Vector3.ZERO, 8))
	parts.append(GroundKit.cyl_part(0.07, 0.09, 3.2, Vector3(0, 9.6, -1.4), Color(0.1, 0.1, 0.1), Vector3(-60, 0, 0), 5, false))
	return _keep("phoenix_bofors", parts)


## Gooseberry blockship: an old merchantman scuttled upright in shallow water, hull and superstructure above water.
static func blockship_mesh() -> ArrayMesh:
	if Scatter._meshes.has("gooseberry_ship"):
		return Scatter._meshes["gooseberry_ship"]
	var hull := Color(0.20, 0.20, 0.21)
	var rust := Color(0.38, 0.24, 0.17)
	var sup := Color(0.55, 0.53, 0.48)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(120.0, 7.5, 16.0), Vector3(0, 3.0, 0), hull))
	parts.append(GroundKit.box_part(Vector3(121.0, 1.0, 16.4), Vector3(0, 0.5, 0), rust, Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(16.0, 8.0, 12.0), Vector3(-6.0, 10.5, 0), sup))
	parts.append(GroundKit.cyl_part(1.8, 2.0, 9.0, Vector3(4.0, 13.0, 0), Color(0.18, 0.17, 0.16), Vector3.ZERO, 8))
	for x in [-40.0, 35.0]:
		parts.append(GroundKit.cyl_part(0.4, 0.45, 16.0, Vector3(x, 14.0, 0), hull, Vector3.ZERO, 5, false))
	parts.append(GroundKit.box_part(Vector3(12.0, 1.0, 14.0), Vector3(-56.0, 7.4, 0), hull, Vector3.ZERO, false))
	return _keep("gooseberry_ship", parts)


## One 24 m span of Whale roadway: the steel bridge deck with its side girders. Along X; sits on a beetle at each end.
static func whale_span_mesh() -> ArrayMesh:
	if Scatter._meshes.has("whale_span"):
		return Scatter._meshes["whale_span"]
	var steel := Color(0.30, 0.31, 0.31)
	var deck := Color(0.40, 0.39, 0.36)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(24.2, 0.25, 3.0), Vector3(0, 0.0, 0), deck))
	for sz in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(24.2, 1.1, 0.25), Vector3(0, -0.5, sz * 1.6), steel, Vector3.ZERO, false))
		parts.append(GroundKit.box_part(Vector3(24.2, 0.08, 0.08), Vector3(0, 1.0, sz * 1.5), steel, Vector3.ZERO, false))
	return _keep("whale_span", parts)


## "Beetle": the concrete (or steel) pontoon a roadway span rests on.
static func beetle_mesh() -> ArrayMesh:
	if Scatter._meshes.has("whale_beetle"):
		return Scatter._meshes["whale_beetle"]
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(5.0, 1.6, 9.0), Vector3(0, 0.3, 0), Color(0.52, 0.51, 0.47)))
	parts.append(GroundKit.box_part(Vector3(5.2, 0.5, 9.2), Vector3(0, -0.2, 0), Color(0.26, 0.28, 0.24), Vector3.ZERO, false))
	return _keep("whale_beetle", parts)


## Spud pierhead: a 61 x 18 m steel pontoon with deck cabins and cranes, riding on four spud legs (separate mesh).
static func pierhead_mesh() -> ArrayMesh:
	if Scatter._meshes.has("spud_pierhead"):
		return Scatter._meshes["spud_pierhead"]
	var steel := Color(0.33, 0.35, 0.35)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(18.0, 3.0, 61.0), Vector3(0, 1.4, 0), steel))
	parts.append(GroundKit.box_part(Vector3(6.0, 3.0, 8.0), Vector3(-4.0, 4.4, -20.0), Color(0.55, 0.55, 0.52)))
	parts.append(GroundKit.box_part(Vector3(1.0, 9.0, 1.0), Vector3(5.0, 7.4, 10.0), Color(0.22, 0.22, 0.22), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(0.6, 0.6, 14.0), Vector3(5.0, 11.5, 5.0), Color(0.22, 0.22, 0.22), Vector3(-20, 0, 0), false))
	return _keep("spud_pierhead", parts)


static func spud_leg_mesh() -> ArrayMesh:
	if Scatter._meshes.has("spud_leg"):
		return Scatter._meshes["spud_leg"]
	var parts: Array = [GroundKit.box_part(Vector3(1.2, 26.0, 1.2), Vector3.ZERO, Color(0.28, 0.29, 0.29), Vector3.ZERO, false)]
	return _keep("spud_leg", parts)


## Bombardon: a cross-section floating breakwater unit, 61 m long, its plus-shaped top showing at the surface.
static func bombardon_mesh() -> ArrayMesh:
	if Scatter._meshes.has("bombardon"):
		return Scatter._meshes["bombardon"]
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(61.0, 1.2, 3.0), Vector3(0, 0.3, 0), Color(0.24, 0.26, 0.26), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(61.0, 3.0, 0.6), Vector3(0, 1.2, 0), Color(0.30, 0.32, 0.31), Vector3.ZERO, false))
	return _keep("bombardon", parts)
