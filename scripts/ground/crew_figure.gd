class_name CrewFigure
extends RefCounted
## Airfield ground crew ("erks" / Warte): proper little people instead of capsules and boxes.
## Each figure is one merged, cached ArrayMesh per (team, pose, dress): jointed legs and arms built from tapered
## segments, a chest and hips, belt, hands, a head with a side cap (or bare hair), and the odd tool in hand.
## Real-world metres (1.78 m tall), standing on y = 0, facing -Z. Swap meshes to animate (WALK_A / WALK_B).
##   CrewFigure.mesh(team, pose, dress) -> ArrayMesh
##   CrewFigure.make(team, pose, dress) -> MeshInstance3D (shadows on, culled beyond ~1.6 km)

enum Pose { STAND, HIPS, POINT, BEND, KNEEL, REACH, WALK_A, WALK_B, CARRY, WAVE }
const DRESSES: int = 4

static var _cache: Dictionary = {}


static func make(team: String, pose: int, dress: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(team, pose, dress)
	mi.visibility_range_end = 1600.0
	mi.visibility_range_end_margin = 150.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


static func mesh(team: String, pose: int, dress: int = 0) -> ArrayMesh:
	var key: String = "%s_%d_%d" % [team, pose, dress % DRESSES]
	if _cache.has(key):
		return _cache[key]
	var m: ArrayMesh = _build(team, pose, dress % DRESSES)
	_cache[key] = m
	return m


# ------------------------------------------------------------------ colours

static func _palette(team: String, dress: int) -> Dictionary:
	var axis: bool = team == "Axis"
	var skin: Color = [Color(0.86, 0.66, 0.53), Color(0.78, 0.58, 0.45), Color(0.90, 0.72, 0.60), Color(0.74, 0.55, 0.42)][dress]
	var hair: Color = [Color(0.22, 0.15, 0.09), Color(0.45, 0.33, 0.18), Color(0.12, 0.10, 0.08), Color(0.55, 0.42, 0.25)][dress]
	var top: Color
	var legs: Color
	var cap: Color
	if axis:
		match dress:
			0:   # black working overalls
				top = Color(0.13, 0.13, 0.14)
				legs = top
			1:   # reed-green / tan drill overalls
				top = Color(0.46, 0.44, 0.35)
				legs = top
			2:   # shirt-sleeves: blue-grey shirt, darker trousers
				top = Color(0.50, 0.54, 0.58)
				legs = Color(0.28, 0.31, 0.36)
			_:   # Fliegerbluse
				top = Color(0.33, 0.37, 0.43)
				legs = Color(0.30, 0.34, 0.40)
		cap = Color(0.30, 0.34, 0.40)
	else:
		match dress:
			0:   # dark blue overalls
				top = Color(0.17, 0.20, 0.28)
				legs = top
			1:   # faded working overalls
				top = Color(0.33, 0.36, 0.40)
				legs = top
			2:   # shirt-sleeves: light blue shirt, blue-grey trousers
				top = Color(0.62, 0.68, 0.76)
				legs = Color(0.27, 0.31, 0.40)
			_:   # battledress blouse
				top = Color(0.30, 0.35, 0.45)
				legs = top
		cap = Color(0.25, 0.30, 0.40)
	return {"skin": skin, "hair": hair, "top": top, "legs": legs, "cap": cap,
		"boot": Color(0.07, 0.06, 0.05), "belt": Color(0.10, 0.09, 0.07) if not axis else Color(0.08, 0.07, 0.06),
		"bare": dress == 2}


# ------------------------------------------------------------------ poses (radians; + pitch swings a limb forward, -Z)

static func _pose(pose: int) -> Dictionary:
	# hip_y, lean, [thigh, knee] L/R, [shoulder pitch, shoulder out, elbow] L/R, head pitch, prop
	var p: Dictionary = {"hip": 0.94, "lean": 0.0, "tl": 0.0, "kl": 0.0, "tr": 0.0, "kr": 0.0,
		"sl": 0.05, "ol": 0.10, "el": -0.15, "sr": 0.05, "or": 0.10, "er": -0.15, "head": 0.0, "prop": ""}
	match pose:
		Pose.HIPS:       # hands on hips, watching
			p.merge({"sl": -0.1, "ol": 0.6, "el": 0.0, "fl": -0.9, "sr": -0.1, "or": 0.6, "er": 0.0, "fr": -0.9, "tl": 0.06, "tr": -0.06}, true)
		Pose.POINT:      # pointing the way / marshalling
			p.merge({"sr": 1.55, "or": 0.25, "er": 0.0, "sl": 0.1, "ol": 0.12, "el": -0.4, "head": -0.05}, true)
		Pose.BEND:       # bent over, working at something low
			p.merge({"hip": 0.90, "lean": 0.85, "tl": -0.15, "kl": 0.0, "tr": 0.10, "kr": 0.0, "sl": 0.6, "ol": 0.12, "el": -0.35, "sr": 0.5, "or": 0.08, "er": -0.55, "head": 0.25, "prop": "spanner"}, true)
		Pose.KNEEL:      # down on one knee by a wheel
			p.merge({"hip": 0.52, "lean": 0.25, "tl": 1.45, "kl": -1.45, "tr": -0.05, "kr": -1.55, "sl": 0.9, "ol": 0.1, "el": -0.6, "sr": 0.7, "or": 0.15, "er": -0.9, "head": 0.15, "prop": "spanner"}, true)
		Pose.REACH:      # reaching up to an engine cowling
			p.merge({"sl": 2.6, "ol": 0.15, "el": -0.3, "sr": 2.4, "or": 0.2, "er": -0.5, "head": -0.35, "tl": 0.1, "tr": -0.1, "prop": "spanner"}, true)
		Pose.WALK_A:
			p.merge({"tl": 0.42, "kl": -0.1, "tr": -0.38, "kr": -0.45, "sl": -0.4, "el": -0.3, "sr": 0.42, "er": -0.45, "hip": 0.92}, true)
		Pose.WALK_B:
			p.merge({"tl": -0.38, "kl": -0.45, "tr": 0.42, "kr": -0.1, "sl": 0.42, "el": -0.45, "sr": -0.4, "er": -0.3, "hip": 0.92}, true)
		Pose.CARRY:      # carrying a can / ammunition box in both hands
			p.merge({"sl": 0.55, "ol": 0.05, "el": -1.0, "sr": 0.55, "or": 0.05, "er": -1.0, "lean": -0.06, "prop": "box"}, true)
		Pose.WAVE:       # waving the pilot off
			p.merge({"sr": 2.7, "or": 0.6, "er": -0.4, "sl": 0.0, "ol": 0.12, "el": -0.2}, true)
	return p


static func _rot(v: Vector3, pitch: float, out: float, side: float) -> Vector3:
	# pitch about X (+ = forward toward -Z for a hanging limb), then swing outward about Z by `out` on `side`
	var r: Vector3 = v.rotated(Vector3.RIGHT, pitch)
	return r.rotated(Vector3.BACK, out * side)


static func _seg(parts: Array, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, segs: int = 7) -> void:
	var d: Vector3 = b - a
	var l: float = d.length()
	if l < 0.001:
		return
	if d.y < 0.0:
		# build every segment pointing upward (an arc from UP to straight DOWN has no unique axis)
		d = -d
		var rt: float = r0
		r0 = r1
		r1 = rt
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = l
	cm.radial_segments = segs
	cm.rings = 1
	var bas := Basis(Quaternion(Vector3.UP, d / l))
	parts.append([cm, Transform3D(bas, (a + b) * 0.5), GroundKit.mat(col, false)])


static func _ball(parts: Array, c: Vector3, r: float, col: Color, sc: Vector3 = Vector3.ONE) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 5
	parts.append([sm, Transform3D(Basis.from_scale(sc), c), GroundKit.mat(col, false)])


static func _boxp(parts: Array, size: Vector3, c: Vector3, bas: Basis, col: Color) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	parts.append([bm, Transform3D(bas, c), GroundKit.mat(col, false)])


static func _build(team: String, pose: int, dress: int) -> ArrayMesh:
	var c: Dictionary = _palette(team, dress)
	var p: Dictionary = _pose(pose)
	var parts: Array = []
	var hip := Vector3(0.0, float(p["hip"]), 0.0)
	var up: Vector3 = Vector3.UP.rotated(Vector3.RIGHT, -float(p["lean"]))      # torso axis (leans toward -Z)
	var tb := Basis(Quaternion(Vector3.UP, up))
	# legs: thigh + shin + boot
	for side in [-1.0, 1.0]:
		var s: String = "l" if side < 0.0 else "r"
		var hj: Vector3 = hip + Vector3(side * 0.10, 0.0, 0.0)
		var th: float = float(p["t" + s])
		var kn: float = float(p["k" + s])
		var knee: Vector3 = hj + _rot(Vector3.DOWN * 0.45, th, 0.0, side)
		var ankle: Vector3 = knee + _rot(Vector3.DOWN * 0.43, th + kn, 0.0, side)
		_seg(parts, hj, knee, 0.085, 0.07, c["legs"])
		_seg(parts, knee, ankle, 0.068, 0.055, c["legs"])
		var fdir: Vector3 = Vector3.FORWARD.rotated(Vector3.RIGHT, th + kn)      # boot follows the shin
		var fb := Basis(Vector3.RIGHT, th + kn)
		_boxp(parts, Vector3(0.11, 0.09, 0.27), ankle + fdir * 0.06 + (fb * Vector3.DOWN) * 0.03, fb, c["boot"])
	# hips, chest, belt
	_boxp(parts, Vector3(0.34, 0.20, 0.21), hip + up * 0.06, tb, c["legs"])
	var chest_c: Vector3 = hip + up * 0.38
	var chest := CylinderMesh.new()       # slightly tapered, broader at the shoulders
	chest.top_radius = 0.20
	chest.bottom_radius = 0.17
	chest.height = 0.50
	chest.radial_segments = 8
	chest.rings = 1
	parts.append([chest, Transform3D(tb * Basis.from_scale(Vector3(1.0, 1.0, 0.62)), chest_c), GroundKit.mat(c["top"], false)])
	_boxp(parts, Vector3(0.36, 0.055, 0.24), hip + up * 0.16, tb, c["belt"])
	# neck and head
	var neck: Vector3 = hip + up * 0.66
	_seg(parts, neck - up * 0.03, neck + up * 0.07, 0.05, 0.05, c["skin"], 6)
	var hup: Vector3 = up.rotated(Vector3.RIGHT, -float(p["head"]))
	var head: Vector3 = neck + hup * 0.17
	_ball(parts, head, 0.11, c["skin"], Vector3(0.92, 1.05, 1.0))
	var hb := Basis(Quaternion(Vector3.UP, hup))
	if bool(c["bare"]):
		_ball(parts, head + hup * 0.03 + hb * Vector3(0, 0, 0.015), 0.112, c["hair"], Vector3(0.95, 0.85, 1.02))
	else:
		_ball(parts, head + hup * 0.02 + hb * Vector3(0, 0, 0.02), 0.108, c["hair"], Vector3(0.95, 0.7, 1.0))
		# side cap: a narrow wedge set on top, tilted a little to the right
		_boxp(parts, Vector3(0.11, 0.075, 0.25), head + hup * 0.105, hb * Basis(Vector3.BACK, -0.18), c["cap"])
	# arms: upper + fore + hand
	var sh_y: Vector3 = hip + up * 0.58
	var hands: Array = []
	for side in [-1.0, 1.0]:
		var s: String = "l" if side < 0.0 else "r"
		var sj: Vector3 = sh_y + tb * Vector3(side * 0.22, 0.0, 0.0)
		var spitch: float = float(p["s" + s])
		var out: float = float(p["o" + s])
		var elbow: Vector3 = sj + _rot(Vector3.DOWN * 0.29, spitch, out, side)
		var wrist: Vector3 = elbow + _rot(Vector3.DOWN * 0.27, spitch - float(p["e" + s]), float(p.get("f" + s, out * 0.6)), side)
		_seg(parts, sj, elbow, 0.058, 0.05, c["top"], 6)
		_seg(parts, elbow, wrist, 0.048, 0.04, c["skin"] if bool(c["bare"]) else c["top"], 6)
		var hand: Vector3 = wrist + (wrist - elbow).normalized() * 0.05
		_ball(parts, hand, 0.045, c["skin"])
		hands.append(hand)
		_ball(parts, sj, 0.065, c["top"])       # shoulder
	# props
	match str(p["prop"]):
		"spanner":
			var h: Vector3 = hands[1]
			_boxp(parts, Vector3(0.03, 0.03, 0.24), h + Vector3(0, 0, -0.09), Basis(Vector3.RIGHT, 0.4), Color(0.55, 0.55, 0.56))
		"box":
			var mid: Vector3 = (hands[0] + hands[1]) * 0.5
			_boxp(parts, Vector3(0.40, 0.26, 0.24), mid + Vector3(0, -0.06, -0.06), Basis.IDENTITY, Color(0.30, 0.33, 0.22) if team != "Axis" else Color(0.33, 0.33, 0.30))
	return AirfieldAssets._build(parts)
