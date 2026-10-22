class_name WingModel
extends RefCounted
## Strip-theory wing. Lift is summed over STATIONS points along each wing (root to tip), every station with its own
##   - angle of attack: the aircraft's angle of attack + roll-rate effect (p * y / V) + dihedral effect of sideslip
##     + wing washout (tips twisted nose-down so the roots stall first) + a small per-aircraft left/right asymmetry
##   - local airspeed: forward speed minus yaw-rate * y (the outer wing of a turn flies faster)
##   - local air density: from the height of that point on the wing (a banked wing tip is higher / lower)
##   - lift coefficient: cambered section, so inverted (negative) lift is only about half as strong; stalls past the
##     critical angle (positive or negative side); flaps cover the inboard FLAP_SPAN of each wing and shift the zero-lift
##     angle, which raises both lift at a given angle and the maximum lift.
## The sums give: total lift along the wing normal in "weights at the stall boundary" (n = 1 is exactly the weight at
## stall speed, sea level, full stall angle), the rolling moment from left/right differences (roll damping, dihedral
## stability, wing drop in a stall), how much of the wing is stalled and which side, and the maximum lift available.

const STATIONS := 6               # per wing
const CL_ALPHA := 5.2             # lift-curve slope per radian
const ALPHA0 := -0.04             # zero-lift angle of the cambered section (rad)
const CRIT := 0.30                # positive stall angle (~17 deg)
const CRIT_NEG := -0.21           # negative stall angle (~-12 deg)
const DIHEDRAL := 0.06
const WASHOUT := 0.045            # rad of tip twist
const FLAP_SPAN := 0.55           # flaps cover the inboard 55% of the half-span
const FLAP_DALPHA0 := -0.10       # zero-lift angle shift at full flap
const FLAP_DCRIT := -0.035        # flaps stall a little earlier
const CL_MAX_REF := CL_ALPHA * (CRIT - ALPHA0)

var half_span: float = 6.0
var ys: PackedFloat32Array = PackedFloat32Array()      # station offsets, + = right wing
var ws: PackedFloat32Array = PackedFloat32Array()      # area weights, sum = 1
var bias: float = 0.0                                  # per-aircraft left/right asymmetry (rad)

# results of the last evaluate()
var n_total: float = 0.0
var roll_moment: float = 0.0
var stall_amount: float = 0.0
var stall_asym: float = 0.0       # > 0: the right wing is more stalled
var n_max_pos: float = 0.0        # maximum upward-in-wing-frame lift available (weights)
var n_max_neg: float = 0.0        # maximum lift available when the wing is flown inverted


func setup(p_half_span: float, seed_v: int) -> void:
	half_span = p_half_span
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	bias = rng.randf_range(-0.012, 0.012)
	ys.clear()
	ws.clear()
	var sum: float = 0.0
	for side in [-1.0, 1.0]:
		for i in STATIONS:
			var t: float = (float(i) + 0.5) / float(STATIONS)
			var chord: float = sqrt(maxf(1.0 - t * t, 0.0))          # elliptical planform
			ys.append(float(side) * t * half_span)
			ws.append(chord)
			sum += chord
	for i in ws.size():
		ws[i] = ws[i] / sum


## Angle of attack that makes the wings carry exactly the weight (1 g) at equivalent airspeed eas with flap
## deployment 0..1: the angle an aircraft trimmed for level flight sits at.
static func trim_alpha(stall_speed: float, eas: float, flap: float) -> float:
	var a0: float = ALPHA0 + 0.5 * FLAP_DALPHA0 * flap
	return clampf(a0 + (CL_MAX_REF / CL_ALPHA) * pow(stall_speed / maxf(eas, 15.0), 2.0), 0.0, 0.25)


## pos / basis: the aircraft's world transform. path_dir: world flight direction. speed: true airspeed.
## alpha_s: signed angle of attack (rad). p / r: roll and yaw rates (rad/s, + = right). ss: sea-level stall speed.
## flap: 0..1 deployment.
func evaluate(pos: Vector3, basis: Basis, path_dir: Vector3, speed: float, alpha_s: float, p: float, r: float, ss: float, flap: float) -> void:
	var vb: Vector3 = basis.inverse() * (path_dir * speed)
	var beta: float = atan2(vb.x, -vb.z)                    # + = relative wind from the right
	var norm: float = ss * ss * CL_MAX_REF
	var tot: float = 0.0
	var mom: float = 0.0
	var stall: float = 0.0
	var s_r: float = 0.0
	var s_l: float = 0.0
	var mp: float = 0.0
	var mn: float = 0.0
	var vspeed: float = maxf(speed, 10.0)
	for i in ys.size():
		var y: float = ys[i]
		var w: float = ws[i]
		var sgn: float = 1.0 if y >= 0.0 else -1.0
		var tt: float = absf(y) / half_span
		var wp: Vector3 = pos + basis.x * y
		var sig: float = exp(-maxf(wp.y / WorldCoords.VERTICAL_SCALE, 0.0) / 8500.0)
		var v: float = maxf(speed - r * y, 0.0)
		var fl: float = flap if tt < FLAP_SPAN else 0.0
		var a0: float = ALPHA0 + FLAP_DALPHA0 * fl
		var crit: float = CRIT + FLAP_DCRIT * fl
		var cl_max: float = CL_ALPHA * (crit - a0)
		var cl_neg: float = CL_ALPHA * (CRIT_NEG - a0)
		var a: float = alpha_s + p * y / vspeed + sgn * DIHEDRAL * beta - WASHOUT * tt * tt
		# the left/right rigging asymmetry only matters as the wing nears the stall (it picks which wing drops);
		# applied all the time it rolled the aircraft off every hard pull
		a += bias * sgn * smoothstep(crit - 0.08, crit, absf(a))
		var cl: float
		var s: float
		if a >= a0:
			cl = minf(CL_ALPHA * (a - a0), cl_max) * (1.0 - 0.5 * smoothstep(crit, crit + 0.15, a))
			s = smoothstep(crit - 0.04, crit + 0.05, a)
			if a > crit + 0.15:
				# deep post-stall: flat-plate behaviour (lift ~ sin 2a, zero at 90 deg, reversed beyond)
				cl = 0.5 * cl_max * sin(2.0 * a) / sin(2.0 * (crit + 0.15))
		else:
			var d: float = CRIT_NEG - a
			cl = maxf(CL_ALPHA * (a - a0), cl_neg) * (1.0 - 0.5 * smoothstep(0.0, 0.15, d))
			s = smoothstep(-0.04, 0.05, d)
			if d > 0.15:
				cl = 0.5 * cl_neg * sin(2.0 * a) / sin(2.0 * (CRIT_NEG - 0.15))
		var q: float = sig * v * v
		var l: float = w * q * cl
		tot += l
		mom += l * (y / half_span)
		stall += w * s
		if y >= 0.0:
			s_r += w * s
		else:
			s_l += w * s
		mp += w * q * cl_max
		mn += w * q * (-cl_neg)
	n_total = tot / norm
	roll_moment = mom / norm
	stall_amount = stall
	stall_asym = (s_r - s_l) * 2.0
	n_max_pos = mp / norm
	n_max_neg = mn / norm
