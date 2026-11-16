shader_type spatial;
render_mode cull_back;
// Airfield ground staff (scripts/ground/airfield_people.gd): every man on a field is one instance of ONE mesh in
// one MultiMesh, and all the movement happens here in the vertex stage - walking, running or marching a beat there
// and back with a proper stride (hips, knees, swinging arms), standing talking, bent over a job, waving, sitting
// on the grass, saluting - and everyone throwing himself flat when the field is attacked (`alarm`). A whole
// airfield is a single draw call; the CPU only feeds two numbers per field (AirfieldPeople.Driver).
//
// Mesh (metres, feet on y = 0, facing -Z):  UV.x = limb (0 body, 1 left leg, 2 right leg, 3 left arm, 4 right arm),
// UV.y = 1 for the part below the knee / elbow (and, on the body, everything above the hips).
// COLOR.a * 10 = what the part is (0 its own COLOR.rgb, 1 top, 2 trousers, 3 side cap, 4 skin, 5 hair, 6 British
// steel helmet, 7 German steel helmet, 8 shin, 9 slung rifle in COLOR.rgb). Ground crew wear their side's working
// dress (top_col / leg_col, four variants) and a side cap. Soldiers (the `soldier` bit: the airfield's drill squad
// and sentries, everyone in an army camp) wear their side's service uniform, jackboots if German; those on duty -
// marching, on sentry, running - also its steel helmet in place of the cap and a slung rifle.
// INSTANCE_CUSTOM = (beat length, walking speed, phase 0..1, kind * 8 + soldier * 4 + dress), lengths in mesh metres.
// kind: 0 walks the beat (-Z, turns, comes back), 1 stands talking, 2 bent over working, 3 waving, 4 runs the
// beat, 5 marches it (a squad shares phase and speed, so it is in step), 6 sits at ease, 7 sentry who salutes,
// 8 wounded man on a stretcher on the ground, 9 medic kneeling over him, 10 rear stretcher bearer, 11 the man on
// the carried stretcher, 12 doctor (stands and talks, in a white coat), 13 front stretcher bearer (10, 11 and 13
// share one beat, phase and speed, so the three move together), 14 passing a football round a ring (.x his place,
// .y the ring's size), 15 the football (.x the ring's size, .y its radius), 16 standing smoking, 17 mechanic reaching
// up into an engine, 18 mechanic kneeling at a wheel, 19 mechanic bent over on a wing (17-19 may stand raised: on a
// work stand or the wing; they never dive for cover).
// UV.y = 2 marks the cigarette, 3 the football; COLOR.a part 10 is the stretcher (posed with nobody).

// the four working dresses of the field's side (plain uniforms, not arrays: they are set from script one by one)
uniform vec3 top0; uniform vec3 top1; uniform vec3 top2; uniform vec3 top3;
uniform vec3 leg0; uniform vec3 leg1; uniform vec3 leg2; uniform vec3 leg3;
uniform vec3 skin0; uniform vec3 skin1; uniform vec3 skin2; uniform vec3 skin3;
uniform vec3 hair0; uniform vec3 hair1; uniform vec3 hair2; uniform vec3 hair3;
uniform vec3 cap_col = vec3(0.05, 0.07, 0.13);
uniform vec3 soldier_top = vec3(0.13, 0.11, 0.04);
uniform vec3 soldier_leg = vec3(0.13, 0.11, 0.04);
uniform vec3 helmet_col = vec3(0.07, 0.08, 0.04);
uniform float axis_side = 0.0;        // 1 on a German field: Stahlhelm and jackboots
// per field (set on the MultiMeshInstance3D): 0..1 as enemy aircraft come over - every man dives flat - and the
// seconds the field's clock has been held back while they lay there (so a walker stops instead of sliding)
instance uniform float alarm = 0.0;
instance uniform float t_off = 0.0;

const float HIP_Y = 0.94;
const float KNEE_Y = 0.49;
const float SH_Y = 1.52;
const float ELB_Y = 1.23;

varying vec3 v_col;
varying float v_emit;

vec3 pick(vec3 a, vec3 b, vec3 c, vec3 d, int i) {
	return (i == 0) ? a : ((i == 1) ? b : ((i == 2) ? c : d));
}

// turn p about the X axis through height py: a positive angle swings a hanging limb forward (-Z)
vec3 rx(vec3 p, float py, float a) {
	float c = cos(a);
	float s = sin(a);
	float y = p.y - py;
	return vec3(p.x, py + y * c - p.z * s, y * s + p.z * c);
}

void vertex() {
	int limb = int(UV.x + 0.5);
	int item = int(UV.y + 0.5);           // 0 / 1 body (1 = below the knee / elbow), 2 cigarette, 3 football
	bool lower = UV.y > 0.5;
	int code = int(INSTANCE_CUSTOM.w + 0.5);
	int kind = code / 8;
	bool soldier = (code - kind * 8) >= 4;
	int pal = code - (code / 4) * 4;
	bool armed = soldier && (kind == 4 || kind == 5 || kind == 7);
	bool medic = kind == 9 || kind == 12;
	float ph = INSTANCE_CUSTOM.z;
	float t = TIME - t_off + ph * 61.0;
	float down = smoothstep(ph * 0.35, ph * 0.35 + 0.65, alarm);      // flat on his face (not all at the same instant)
	if (kind == 8 || kind == 10 || kind == 11 || kind == 13 || kind == 15 || kind >= 17) {
		down = 0.0;           // the wounded stay on their stretchers, the bearers keep going, mechanics stay at their work
	}
	float sit = 0.0;
	float lie = 0.0;       // 1: lying on his back on a stretcher (patients)
	float lie_h = 0.0;     // ...and how high the stretcher holds him
	float carry_h = 0.0;   // height of a carried stretcher's poles above the ground stretcher's

	float th_l = 0.0;      // thighs
	float th_r = 0.0;
	float kn_l = 0.0;      // knees (negative folds the shin back)
	float kn_r = 0.0;
	float ar_l = 0.04;     // shoulders
	float ar_r = 0.04;
	float el_l = 0.18;     // elbows (positive brings the forearm forward)
	float el_r = 0.18;
	float lean = 0.0;      // the body bent forward at the hips
	float yaw = 0.0;
	float adv = 0.0;       // metres walked along -Z
	float bob = 0.0;
	vec3 ball = vec3(0.0); // the football's offset (kind 15)

	if (kind == 0 || kind == 4 || kind == 5 || kind == 10 || kind == 11 || kind == 13) {
		// stride length, hip swing, knee fold, arm swing, elbow, forward lean, bob - walk / run / march / bearers
		float stride = 1.5;
		float a_th = 0.46;
		float a_kn = 0.80;
		float a_ar = 0.36;
		float a_el = 0.22;
		float a_bob = 0.022;
		float run_lean = 0.0;
		float halt = 2.4;
		if (kind == 4) {
			stride = 2.7;
			a_th = 0.85;
			a_kn = 1.55;
			a_ar = 0.85;
			a_el = 1.30;
			a_bob = 0.05;
			run_lean = 0.22;
			halt = 1.2;
		} else if (kind == 5) {
			a_th = 0.52;
			a_kn = 0.55;
			a_ar = 0.62;                                 // arms swung straight, shoulder high
			a_el = 0.0;
			a_bob = 0.012;
			halt = 3.0;
		} else if (kind >= 10) {
			stride = 1.15;                               // short, careful steps under the weight
			a_th = 0.30;
			a_kn = 0.50;
			a_ar = 0.0;
			a_el = 0.0;
			a_bob = 0.015;
			halt = 3.5;
		}
		float len = max(INSTANCE_CUSTOM.x, 0.5);
		float spd = max(INSTANCE_CUSTOM.y, 0.1);
		float pause = halt * spd;                      // a few seconds turning round at each end
		float lap = 2.0 * (len + pause);
		float d = mod(t * spd, lap);
		float w = 1.0;
		if (d < len) {
			adv = d;
		} else if (d < len + pause) {
			adv = len;
			w = 0.0;
			yaw = PI * smoothstep(0.0, 1.0, (d - len) / pause);
		} else if (d < 2.0 * len + pause) {
			adv = 2.0 * len + pause - d;
			yaw = PI;
		} else {
			w = 0.0;
			yaw = PI * (1.0 + smoothstep(0.0, 1.0, (d - 2.0 * len - pause) / pause));
		}
		w *= smoothstep(0.0, 0.5, min(adv, len - adv));          // into and out of the stride at the ends
		float g = d * (TAU / stride);
		th_l = a_th * sin(g) * w;
		th_r = -th_l;
		kn_l = -a_kn * max(0.0, cos(g)) * w - 0.06 * w;           // the leg coming forward folds at the knee
		kn_r = -a_kn * max(0.0, -cos(g)) * w - 0.06 * w;
		ar_l = 0.04 - a_ar * sin(g) * w;
		ar_r = 0.04 + a_ar * sin(g) * w;
		el_l = 0.18 + a_el * w;
		el_r = el_l;
		lean = run_lean * w;
		ar_l += lean;                                             // (arms hang from a leaning body)
		ar_r += lean;
		bob = a_bob * cos(2.0 * g) * w;
		// on the way back the two bearers have turned round: the one behind the stretcher now is the other man
		bool back_trip = yaw > 1.5708 && yaw < 4.7124;
		if ((kind == 10 || kind == 13) && ((kind == 10) != back_trip)) {
			// rear bearer: both hands out in front on the handles
			ar_l = 0.30;
			ar_r = 0.30;
			el_l = 0.45;
			el_r = 0.45;
		} else if (kind == 10 || kind == 13) {
			// front bearer: arms straight down at his sides, the handles in his fists behind him
			ar_l = -0.08;
			ar_r = -0.08;
			el_l = 0.05;
			el_r = 0.05;
		} else if (kind == 11) {
			// the man on the carried stretcher
			th_l = 0.0;
			th_r = 0.0;
			kn_l = 0.0;
			kn_r = 0.0;
			ar_l = 0.0;
			ar_r = 0.0;
			el_l = 0.1;
			el_r = 0.1;
			lean = 0.0;
			bob = 0.0;
			lie = 1.0;
			carry_h = 0.78;
			lie_h = 0.30 + carry_h;
		}
	} else if (kind == 1 || kind == 12) {
		float talk = smoothstep(0.25, 0.9, sin(t * 0.47 + ph * 19.0));     // now and then a hand comes up to make a point
		ar_r = 0.04 + 0.75 * talk + 0.10 * talk * sin(t * 4.0);
		el_r = 0.18 + 1.25 * talk;
		ar_l = 0.04 + 0.05 * sin(t * 0.6);
		yaw = 0.30 * sin(t * 0.21 + ph * 7.0);                             // looking about
		th_l = 0.04 * sin(t * 0.33);                                       // shifting his weight
		th_r = -th_l;
	} else if (kind == 2 || kind == 19) {
		lean = 0.78 + 0.06 * sin(t * 1.3);
		ar_l = lean + 0.30 + 0.28 * sin(t * 3.3);
		ar_r = lean + 0.30 + 0.28 * sin(t * 3.3 + 2.1);
		el_l = 0.55;
		el_r = 0.55;
		th_l = 0.10;
		th_r = -0.14;
	} else if (kind == 3) {
		ar_r = 2.75 + 0.22 * sin(t * 5.2);
		el_r = 0.30 + 0.35 * sin(t * 5.2 + 1.0);
		yaw = 0.12 * sin(t * 0.4);
	} else if (kind == 6) {
		// at ease on the grass: sat with his knees up, leaning back on his hands, looking about
		sit = 1.0;
		th_l = 1.90 + 0.05 * sin(t * 0.25 + ph * 9.0);
		th_r = 1.78;
		kn_l = -1.00;
		kn_r = -0.92;
		lean = -0.32 + 0.03 * sin(t * 0.4);
		ar_l = lean - 0.55;
		ar_r = lean - 0.50;
		el_l = 0.05;
		el_r = 0.05;
		yaw = 0.35 * sin(t * 0.17 + ph * 5.0);
	} else if (kind == 8) {
		// wounded, lying on a stretcher on the ground: still, now and then a hand moves
		lie = 1.0;
		lie_h = 0.30;
		ar_l = 0.0;
		ar_r = 0.22 * smoothstep(0.6, 0.95, sin(t * 0.31 + ph * 13.0));
		el_r = 0.1 + ar_r * 2.0;
		el_l = 0.1;
	} else if (kind == 9 || kind == 18) {
		// medic down on one knee beside a stretcher, working on the man on it
		th_l = -0.10;
		kn_l = -1.60;
		th_r = 1.50;
		kn_r = -1.50;
		lean = 0.45 + 0.05 * sin(t * 0.9);
		ar_l = lean + 0.55 + 0.22 * sin(t * 3.1);
		ar_r = lean + 0.62 + 0.22 * sin(t * 3.1 + 1.9);
		el_l = 0.50;
		el_r = 0.55;
		yaw = 0.10 * sin(t * 0.37 + ph * 3.0);
	} else if (kind == 14) {
		// passing a football round a ring: INSTANCE_CUSTOM.x = his place in the ring, .y = how many in it
		float n_ring = max(INSTANCE_CUSTOM.y, 2.0);
		float me = INSTANCE_CUSTOM.x;
		float step_n = (n_ring > 4.5) ? 2.0 : 1.0;
		float tt = t / 1.7;
		float i_pass = floor(tt);
		float f = tt - i_pass;
		float from = mod(i_pass * step_n, n_ring);
		float to = mod((i_pass + 1.0) * step_n, n_ring);
		float kick = (abs(from - me) < 0.5) ? sin(PI * clamp(f / 0.22, 0.0, 1.0)) : 0.0;
		float trap = (abs(to - me) < 0.5) ? smoothstep(0.70, 0.92, f) * (1.0 - smoothstep(0.95, 1.0, f)) : 0.0;
		th_r = -0.35 * kick + 1.05 * kick * smoothstep(0.08, 0.20, f) + 0.35 * trap;
		kn_r = -0.9 * kick * (1.0 - smoothstep(0.08, 0.2, f));
		th_l = 0.06 * sin(t * 1.3);
		ar_l = 0.25 * kick + 0.06;
		ar_r = -0.25 * kick + 0.06;
		lean = 0.10 * kick + 0.12 * trap;
		bob = 0.015 * sin(t * 3.0);
	} else if (kind == 15) {
		// the football itself (an instance with only the ball shown): flies from one man's feet to the next
		float n_ring2 = max(INSTANCE_CUSTOM.x, 2.0);
		float rr = INSTANCE_CUSTOM.y * 0.86;
		float step2 = (n_ring2 > 4.5) ? 2.0 : 1.0;
		float tt2 = t / 1.7;
		float i2 = floor(tt2);
		float f2 = smoothstep(0.12, 0.88, tt2 - i2);
		float a_from = TAU * mod(i2 * step2, n_ring2) / n_ring2;
		float a_to = TAU * mod((i2 + 1.0) * step2, n_ring2) / n_ring2;
		vec3 pf = vec3(cos(a_from), 0.0, sin(a_from)) * rr;
		vec3 pt = vec3(cos(a_to), 0.0, sin(a_to)) * rr;
		ball = mix(pf, pt, f2) + vec3(0.0, 0.55 * sin(PI * f2), 0.0);
	} else if (kind == 17) {
		// mechanic up at an engine (on a work stand, a trestle or the ground): both arms up in the cowling
		ar_l = 2.05 + 0.22 * sin(t * 2.7 + ph * 5.0);
		ar_r = 1.85 + 0.30 * sin(t * 2.3 + 1.0);
		el_l = 0.65 + 0.30 * sin(t * 3.1);
		el_r = 0.80 + 0.30 * sin(t * 2.9 + 2.0);
		lean = 0.06 + 0.04 * sin(t * 0.7);
		yaw = 0.10 * sin(t * 0.33 + ph * 4.0);
		th_l = 0.05;
		th_r = -0.05;
	} else if (kind == 16) {
		// standing smoking: the cigarette goes to his lips every few seconds, the other hand in his pocket
		float cyc = mod(t * 0.13 + ph * 3.7, 1.0);
		float up = smoothstep(0.0, 0.10, cyc) * (1.0 - smoothstep(0.24, 0.34, cyc));
		ar_r = 0.10 + 0.68 * up;
		el_r = 0.55 + 1.85 * up;
		ar_l = -0.12;
		el_l = 0.35;
		yaw = 0.18 * sin(t * 0.19 + ph * 9.0);
		th_l = 0.05;
		th_r = -0.03;
	} else {
		// sentry: at attention, and every so often a salute held for a couple of seconds
		float sal = smoothstep(0.50, 0.72, sin(t * 0.5 + ph * 11.0));
		ar_r = 0.02 + 1.28 * sal;
		el_r = 0.10 + 2.15 * sal;
		ar_l = 0.02;
		el_l = 0.08;
	}
	// under attack: limbs straighten, arms go over the head, and the whole man goes flat (below)
	sit *= 1.0 - down;
	th_l *= 1.0 - down;
	th_r *= 1.0 - down;
	kn_l *= 1.0 - down;
	kn_r *= 1.0 - down;
	lean *= 1.0 - down;
	ar_l = mix(ar_l, 2.85, down);
	ar_r = mix(ar_r, 2.95, down);
	el_l = mix(el_l, 0.9, down);
	el_r = mix(el_r, 0.8, down);
	bob *= 1.0 - down;

	vec3 v = VERTEX;
	vec3 n = NORMAL;
	int part = int(COLOR.a * 10.0 + 0.5);
	// headgear, rifle, cigarette, ball and stretcher that this man does not have are folded away (a degenerate point)
	bool hide = (part == 3 && (armed || medic)) || (part == 9 && !armed) || (part == 6 && (!armed || axis_side > 0.5))
		|| (part == 7 && (!armed || axis_side < 0.5)) || (part == 10 && kind != 8 && kind != 11)
		|| (item == 2 && kind != 16) || (item == 3) != (kind == 15);
	if (hide) {
		v = vec3(0.0, 1.72, 0.0);
	}
	if (kind == 15) {
		v += ball;
	} else if (part == 10) {
		v.y += carry_h;                       // the stretcher: not posed with the man, carried at the bearers' hands
	} else {
		if (limb == 1 || limb == 2) {
			float th = (limb == 1) ? th_l : th_r;
			float kn = (limb == 1) ? kn_l : kn_r;
			if (lower) {
				v = rx(v, KNEE_Y, kn);
				n = rx(n, 0.0, kn);
			}
			v = rx(v, HIP_Y, th);
			n = rx(n, 0.0, th);
		} else if (limb == 3 || limb == 4) {
			float ar = (limb == 3) ? ar_l : ar_r;
			float el = (limb == 3) ? el_l : el_r;
			if (lower) {
				v = rx(v, ELB_Y, el);
				n = rx(n, 0.0, el);
			}
			v = rx(v, SH_Y, ar);
			n = rx(n, 0.0, ar);
			v = rx(v, HIP_Y, -lean);
			n = rx(n, 0.0, -lean);
		} else if (lower) {
			v = rx(v, HIP_Y, -lean);
			n = rx(n, 0.0, -lean);
		}
		// keep his boots on the ground: a swinging leg lifts its foot, so the body is lowered by however far the
		// lower of the two feet has risen (hips fixed in the air is what makes a walking figure look as if it hovers)
		float lift_l = HIP_Y - (0.45 * cos(th_l) + 0.49 * cos(th_l + kn_l));
		float lift_r = HIP_Y - (0.45 * cos(th_r) + 0.49 * cos(th_r + kn_r));
		float settle = max(min(lift_l, lift_r), 0.0) * (1.0 - sit) * (1.0 - lie);
		v.y += bob * 0.4 - settle - sit * (HIP_Y - 0.13);
		// thrown flat: pitched forward about his boots, face down, lying on the thickness of his chest
		v = rx(v, 0.0, -1.50 * down);
		n = rx(n, 0.0, -1.50 * down);
		v.y += 0.13 * down;
		// a patient: laid on his back (head toward +Z), centred on the stretcher and up at its height
		if (lie > 0.5) {
			v = rx(v, 0.0, 1.5708);
			n = rx(n, 0.0, 1.5708);
			v.z -= 0.9;
			v.y += lie_h;
		}
	}
	float cy = cos(yaw);
	float sy = sin(yaw);
	v = vec3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy);
	n = vec3(n.x * cy + n.z * sy, n.y, -n.x * sy + n.z * cy);
	v.z -= adv;
	VERTEX = v;
	NORMAL = normalize(n);

	vec3 c = COLOR.rgb;
	v_emit = 0.0;
	if (part == 1) {
		c = medic ? vec3(0.80, 0.80, 0.77) : (soldier ? soldier_top : pick(top0, top1, top2, top3, pal));
	} else if (part == 2) {
		c = (kind == 12) ? vec3(0.78, 0.78, 0.75) : (soldier ? soldier_leg : pick(leg0, leg1, leg2, leg3, pal));
	} else if (part == 8) {
		c = soldier ? ((axis_side > 0.5) ? vec3(0.006, 0.005, 0.004) : soldier_leg) : pick(leg0, leg1, leg2, leg3, pal);
	} else if (part == 6 || part == 7) {
		c = helmet_col;
	} else if (part == 3) {
		c = soldier ? soldier_top * 0.8 : cap_col;
	} else if (part == 4) {
		c = pick(skin0, skin1, skin2, skin3, pal);
	} else if (part == 5) {
		c = pick(hair0, hair1, hair2, hair3, pal);
	}
	if (item == 2 && c.r > 0.5 && c.g < 0.3) {
		v_emit = 2.5;                         // the lit end of the cigarette
	}
	v_col = c;
}

void fragment() {
	ALBEDO = v_col;
	EMISSION = v_col * v_emit;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
