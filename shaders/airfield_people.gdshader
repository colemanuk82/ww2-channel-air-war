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
// The towns dress the same figure as civilians: dress 8-15 pick the town wardrobe below (suit, tweed, overcoat,
// a woman's coat or dress with a skirt, a constable, an ARP warden, a Home Guard patrol).
// INSTANCE_CUSTOM = (beat length, walking speed, phase 0..1, kind * 64 + soldier * 32 + dress), lengths in mesh metres.
// kind: 0 walks the beat (-Z, turns, comes back), 1 stands talking, 2 bent over working, 3 waving, 4 runs the
// beat, 5 marches it (a squad shares phase and speed, so it is in step), 6 sits at ease, 7 sentry who salutes,
// 8 wounded man on a stretcher on the ground, 9 medic kneeling over him, 10 rear stretcher bearer, 11 the man on
// the carried stretcher, 12 doctor (stands and talks, in a white coat), 13 front stretcher bearer (10, 11 and 13
// share one beat, phase and speed, so the three move together), 14 passing a football round a ring (.x his place,
// .y the ring's size), 15 the football (.x the ring's size, .y its radius), 16 standing smoking, 17 mechanic reaching
// up into an engine, 18 mechanic kneeling at a wheel, 19 mechanic bent over on a wing (17-19 may stand raised: on a
// work stand or the wing; they never dive for cover), 20 stands in a queue and shuffles, 21 rides a bicycle,
// 22 pushes a pram, 23 stands in a knot at a corner talking with both hands.
// UV.y = 2 marks the cigarette, 3 the football; COLOR.a part 10 is the stretcher, 11 the bicycle (a CYCLE), 12 the
// pram (a PRAM) and 13 the skirt (women only) - all posed with nobody.

// the four working dresses of the field's side (plain uniforms, not arrays: they are set from script one by one)
uniform vec3 top0; uniform vec3 top1; uniform vec3 top2; uniform vec3 top3;
uniform vec3 leg0; uniform vec3 leg1; uniform vec3 leg2; uniform vec3 leg3;
uniform vec3 skin0; uniform vec3 skin1; uniform vec3 skin2; uniform vec3 skin3;
uniform vec3 hair0; uniform vec3 hair1; uniform vec3 hair2; uniform vec3 hair3;
uniform vec3 cap_col = vec3(0.05, 0.07, 0.13);
uniform vec3 soldier_top = vec3(0.13, 0.11, 0.04);
uniform vec3 soldier_leg = vec3(0.13, 0.11, 0.04);
uniform vec3 helmet_col = vec3(0.07, 0.08, 0.04);
// the town wardrobe (dress 8-15): dark suit, tweed jacket, overcoat, a woman's long coat, a woman's summer dress,
// a constable, an ARP warden and a Home Guard patrol (the last in the soldier's own uniform)
uniform vec3 civ_top0; uniform vec3 civ_top1; uniform vec3 civ_top2; uniform vec3 civ_top3;
uniform vec3 civ_top4; uniform vec3 civ_top5; uniform vec3 civ_top6; uniform vec3 civ_top7;
uniform vec3 civ_leg0; uniform vec3 civ_leg1; uniform vec3 civ_leg2; uniform vec3 civ_leg3;
uniform vec3 civ_leg4; uniform vec3 civ_leg5; uniform vec3 civ_leg6; uniform vec3 civ_leg7;
uniform vec3 civ_cap0; uniform vec3 civ_cap1; uniform vec3 civ_cap2; uniform vec3 civ_cap3;
uniform vec3 civ_cap4; uniform vec3 civ_cap5; uniform vec3 civ_cap6; uniform vec3 civ_cap7;
uniform vec3 civ_helmet_col = vec3(0.006, 0.008, 0.018);   // the constable's and warden's dark navy helmet
// the farm wardrobe (dress 16-20, Phase 2 farms): English farmer (waistcoat over shirt sleeves, flat cap), Women's Land
// Army (green jumper, brown breeches, slouch hat), farm boy (short, grey trousers, cap), French farmer (blue smock,
// beret), French farm woman (dark dress, headscarf, skirt). farm_arm is the sleeve colour (the body takes farm_top).
uniform vec3 farm_top0; uniform vec3 farm_top1; uniform vec3 farm_top2; uniform vec3 farm_top3; uniform vec3 farm_top4;
uniform vec3 farm_arm0; uniform vec3 farm_arm1; uniform vec3 farm_arm2; uniform vec3 farm_arm3; uniform vec3 farm_arm4;
uniform vec3 farm_leg0; uniform vec3 farm_leg1; uniform vec3 farm_leg2; uniform vec3 farm_leg3; uniform vec3 farm_leg4;
uniform vec3 farm_cap0; uniform vec3 farm_cap1; uniform vec3 farm_cap2; uniform vec3 farm_cap3; uniform vec3 farm_cap4;
// the gendarme (dress 21, French towns): dark blue tunic and trousers, a kepi
uniform vec3 gend_top = vec3(0.01, 0.015, 0.05);
uniform vec3 gend_leg = vec3(0.01, 0.014, 0.04);
uniform vec3 gend_cap = vec3(0.012, 0.02, 0.07);
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

// the town wardrobe: eight outfits, picked without a dynamic uniform-array index (i is dress - 8)
vec3 civ_pick(vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f, vec3 g, vec3 h, int i) {
	if (i < 1) { return a; }
	if (i < 2) { return b; }
	if (i < 3) { return c; }
	if (i < 4) { return d; }
	if (i < 5) { return e; }
	if (i < 6) { return f; }
	if (i < 7) { return g; }
	return h;
}
vec3 civ_top_c(int d) { return civ_pick(civ_top0, civ_top1, civ_top2, civ_top3, civ_top4, civ_top5, civ_top6, civ_top7, d - 8); }
vec3 civ_leg_c(int d) { return civ_pick(civ_leg0, civ_leg1, civ_leg2, civ_leg3, civ_leg4, civ_leg5, civ_leg6, civ_leg7, d - 8); }
vec3 civ_cap_c(int d) { return civ_pick(civ_cap0, civ_cap1, civ_cap2, civ_cap3, civ_cap4, civ_cap5, civ_cap6, civ_cap7, d - 8); }

// the farm wardrobe: five outfits (i is dress - 16), again without a dynamic uniform-array index
vec3 farm_pick(vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, int i) {
	if (i < 1) { return a; }
	if (i < 2) { return b; }
	if (i < 3) { return c; }
	if (i < 4) { return d; }
	return e;
}
vec3 farm_top_c(int d) { return farm_pick(farm_top0, farm_top1, farm_top2, farm_top3, farm_top4, d - 16); }
vec3 farm_arm_c(int d) { return farm_pick(farm_arm0, farm_arm1, farm_arm2, farm_arm3, farm_arm4, d - 16); }
vec3 farm_leg_c(int d) { return farm_pick(farm_leg0, farm_leg1, farm_leg2, farm_leg3, farm_leg4, d - 16); }
vec3 farm_cap_c(int d) { return farm_pick(farm_cap0, farm_cap1, farm_cap2, farm_cap3, farm_cap4, d - 16); }

// turn p about the X axis through height py: a positive angle swings a hanging limb forward (-Z)
vec3 rx(vec3 p, float py, float a) {
	float c = cos(a);
	float s = sin(a);
	float y = p.y - py;
	return vec3(p.x, py + y * c - p.z * s, y * s + p.z * c);
}

void vertex() {
	int limb = int(UV.x + 0.5);
	bool bigpart = UV.y > 50.0;           // parts 10 and up ride in UV.y as 100 + part (the colour alpha is an 8-bit unorm: a / 10 > 1 would clamp)
	int item = bigpart ? 1 : int(UV.y + 0.5);           // 0 / 1 body (1 = below the knee / elbow), 2 cigarette, 3 football
	bool lower = bigpart || UV.y > 0.5;
	int code = int(INSTANCE_CUSTOM.w + 0.5);
	int kind = code / 64;                       // INSTANCE_CUSTOM.w = kind * 64 + soldier * 32 + dress
	int cbit = code - kind * 64;
	bool soldier = cbit >= 32;
	int dress = cbit - (soldier ? 32 : 0);      // 0-3 the side's working dress, 8-15 the town wardrobe
	int pal = dress - (dress / 4) * 4;
	bool civ = dress >= 8;
	bool armed = soldier && (civ || kind == 4 || kind == 5 || kind == 7);
	bool medic = kind == 9 || kind == 12;
	bool tin = civ ? (soldier || dress == 13 || dress == 14) : armed;    // a helmet in place of the cap
	bool brodie = tin && axis_side < 0.5;
	bool stahl = tin && axis_side > 0.5;
	bool gend = dress == 21;                    // the gendarme
	bool farm = dress >= 16 && !gend;           // the farm wardrobe 16-20 (Phase 2)
	bool skirt = civ && (dress == 11 || dress == 12 || dress == 20);
	float ph = INSTANCE_CUSTOM.z;
	// kinds 26-28 (leading a horse, driving a cart / tractor, behind the plough) move rigidly with the horse team /
	// cart / plough prop that shares their beat (shaders/farm_props.gdshader): they ignore the raid's held-back clock
	float t = TIME - ((kind >= 26) ? 0.0 : t_off) + ph * 61.0;
	float down = smoothstep(ph * 0.35, ph * 0.35 + 0.65, alarm);      // flat on his face (not all at the same instant)
	if (kind == 8 || kind == 10 || kind == 11 || kind == 13 || kind == 15 || (kind >= 17 && kind <= 19) || kind >= 26) {
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

	if (kind == 0 || kind == 4 || kind == 5 || kind == 10 || kind == 11 || kind == 13 || kind == 21 || kind == 22 || kind >= 26) {
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
		} else if (kind == 21) {
			// the rider: up on the saddle, leaning a little, the legs turning the pedals
			float ped = t * 4.2 + ph * 6.283;
			float pw = max(w, 0.45);
			th_l = 0.66 + 0.30 * sin(ped) * pw;
			th_r = 0.66 + 0.30 * sin(ped + PI) * pw;
			kn_l = -1.05 - 0.28 * cos(ped) * pw;
			kn_r = -1.05 - 0.28 * cos(ped + PI) * pw;
			ar_l = 0.86 + 0.03 * sin(ped * 0.5);
			ar_r = 0.86 + 0.03 * sin(ped * 0.5 + 1.7);
			el_l = 0.30;
			el_r = 0.30;
			lean = 0.16;
			bob = 0.006 * sin(ped * 2.0) * pw;
		} else if (kind == 22) {
			// pushing the pram: both hands out on the handle, unhurried steps
			ar_l = 0.84 + 0.03 * sin(t * 1.1 + ph * 4.0);
			ar_r = 0.84 + 0.03 * sin(t * 1.1 + ph * 4.0 + 0.9);
			el_l = 0.34;
			el_r = 0.34;
			lean = 0.06;
		} else if (kind == 26) {
			// leading a horse: the right hand up at the halter beside its head, the left swinging, an easy stride
			ar_r = 0.80 + 0.03 * sin(t * 1.3 + ph * 4.0);
			el_r = 0.80;
			ar_l = 0.04 - 0.30 * sin(g) * w;
			el_l = 0.18 + 0.20 * w;
			lean = 0.03;
		} else if (kind == 27) {
			// sat up on the cart's seat or the tractor's: thighs level, shins hanging, both hands forward on the reins /
			// the wheel, rocking a little with the going
			float rock = sin(t * 2.1 + ph * 5.0);
			th_l = 1.50;
			th_r = 1.50;
			kn_l = -0.25 + 0.04 * rock;
			kn_r = -0.30;
			ar_l = 0.74 + 0.04 * rock;
			ar_r = 0.80 + 0.04 * rock;
			el_l = 0.55;
			el_r = 0.60;
			lean = 0.10;
			sit = 1.0;
			bob = 0.020 * rock * w;
		} else if (kind == 28) {
			// behind the plough: both hands forward and low on the handles, leaning into it, a slow steady pace
			ar_l = 0.62 + 0.03 * sin(t * 1.7);
			ar_r = 0.62 + 0.03 * sin(t * 1.7 + 1.0);
			el_l = 0.30;
			el_r = 0.30;
			lean = 0.16;
			ar_l += lean;
			ar_r += lean;
		}
	} else if (kind == 24) {
		// forking hay or stooks: a 3 s cycle, the tines driven into the heap with the body bent into it, then up and
		// over in a toss; the arms' net swing is theta (see the hoe), the pole of the fork runs on from the forearm
		float fc = 0.5 + 0.5 * sin(t * 2.1 + ph * 6.2832);
		float fs = smoothstep(0.10, 0.90, fc);
		lean = mix(0.55, 0.08, fs);
		float th_f = mix(1.00, 2.20, fs);
		ar_l = th_f + lean;
		ar_r = th_f + lean + 0.05;
		el_l = mix(0.12, 0.40, fs);
		el_r = el_l;
		th_l = mix(0.30, 0.05, fs);
		th_r = mix(-0.25, -0.05, fs);
		kn_l = -0.12 * (1.0 - fs);
		yaw = 0.22 * sin(t * 0.17 + ph * 7.0) * fs;
	} else if (kind == 25) {
		// hoeing: bent well over, both hands on the hoe, a chop every 2.8 s with the blade at the ground
		float hc = 0.5 + 0.5 * sin(t * 2.25 + ph * 6.2832);
		lean = 0.75 + 0.05 * hc;
		float th_h = 0.79 + 0.17 * hc;
		ar_l = th_h + lean;
		ar_r = th_h + lean + 0.03;
		el_l = 0.05;
		el_r = 0.05;
		th_l = 0.26;
		th_r = -0.22;
		kn_l = -0.08;
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
	} else if (kind == 20) {
		// standing in a queue: hands hanging or in pockets, now and then a shuffle of the feet and a look about
		float qc = fract(t * 0.11 + ph * 5.0);
		float sh = smoothstep(0.60, 0.68, qc) * (1.0 - smoothstep(0.74, 0.86, qc));
		th_l = 0.20 * sh;
		th_r = -0.10 * sh;
		kn_l = -0.36 * sh;
		ar_l = -0.10 + 0.05 * sin(t * 0.7 + ph * 3.0);
		ar_r = -0.06;
		el_l = 0.26;
		el_r = 0.22;
		yaw = 0.14 * sin(t * 0.23 + ph * 8.0) + 0.10 * sin(t * 1.7);
		lean = 0.04;
	} else if (kind == 23) {
		// a knot at a corner: talking with both hands, laughing, turning from one to the other
		float tal = smoothstep(0.30, 0.85, sin(t * 0.62 + ph * 23.0));
		ar_l = 0.30 + 0.55 * tal + 0.12 * sin(t * 3.7 + ph * 5.0);
		ar_r = 0.30 + 0.40 * (1.0 - tal) + 0.12 * sin(t * 3.1 + ph * 7.0);
		el_l = 0.60 + 0.70 * tal;
		el_r = 0.60 + 0.55 * (1.0 - tal);
		yaw = 0.42 * sin(t * 0.31 + ph * 11.0);
		lean = 0.06 + 0.05 * sin(t * 0.9 + ph * 4.0);
		th_l = 0.05 * sin(t * 0.5);
		th_r = -th_l;
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
	int part = bigpart ? int(UV.y + 0.5) - 100 : int(COLOR.a * 10.0 + 0.5);
	// headgear, rifle, cigarette, ball, stretcher, bicycle, pram and skirt that this figure does not have are folded
	// away (a degenerate point)
	bool hide = (part == 3 && (tin || medic || (civ && dress == 11))) || (part == 9 && !armed)
		|| (part == 6 && !brodie) || (part == 7 && !stahl)
		|| (part == 10 && kind != 8 && kind != 11) || (part == 11 && kind != 21) || (part == 12 && kind != 22)
		|| (part == 13 && !skirt) || (item == 2 && kind != 16) || (item == 3) != (kind == 15)
		|| (part == 14 && kind != 24) || (part == 15 && kind != 25);
	if (hide) {
		v = vec3(0.0, 1.72, 0.0);
	}
	if (kind == 15) {
		v += ball;
	} else if (part == 10) {
		v.y += carry_h;                       // the stretcher: not posed with the man, carried at the bearers' hands
	} else {
		bool prop = part == 11 || part == 12;     // the bicycle and the pram go with the rider / pusher, not his legs
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
		} else if (!prop && lower) {
			v = rx(v, HIP_Y, -lean);
			n = rx(n, 0.0, -lean);
		}
		// keep his boots on the ground: a swinging leg lifts its foot, so the body is lowered by however far the
		// lower of the two feet has risen (hips fixed in the air is what makes a walking figure look as if it hovers)
		float lift_l = HIP_Y - (0.45 * cos(th_l) + 0.49 * cos(th_l + kn_l));
		float lift_r = HIP_Y - (0.45 * cos(th_r) + 0.49 * cos(th_r + kn_r));
		// (a cyclist's legs are bent to the pedals, so he is not lowered to keep his boots on the road; the bicycle
		// and the pram are not lowered at all)
		float settle = max(min(lift_l, lift_r), 0.0) * (1.0 - sit) * (1.0 - lie) * (kind == 21 ? 0.0 : 1.0) * (prop ? 0.0 : 1.0);
		v.y += prop ? 0.0 : (bob * 0.4 - settle - sit * (HIP_Y - 0.13));
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
	if (dress == 18) {
		v *= 0.80;                            // the farm boy: a head shorter (the tools in his hands shrink with him)
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
		vec3 ctop = farm ? ((limb == 0) ? farm_top_c(dress) : farm_arm_c(dress)) : civ_top_c(dress);    // farmer: waistcoat, shirt sleeves
		if (gend) { ctop = gend_top; }
		c = medic ? vec3(0.80, 0.80, 0.77) : (soldier ? soldier_top : (civ ? ctop : pick(top0, top1, top2, top3, pal)));
	} else if (part == 2) {
		vec3 cleg = gend ? gend_leg : (farm ? farm_leg_c(dress) : civ_leg_c(dress));
		c = (kind == 12) ? vec3(0.78, 0.78, 0.75) : (soldier ? soldier_leg : (civ ? cleg : pick(leg0, leg1, leg2, leg3, pal)));
	} else if (part == 8) {
		vec3 cshin = (gend ? gend_leg : (farm ? farm_leg_c(dress) : civ_leg_c(dress))) * 0.6;
		c = soldier ? ((axis_side > 0.5) ? vec3(0.006, 0.005, 0.004) : soldier_leg) : (civ ? cshin : pick(leg0, leg1, leg2, leg3, pal));
	} else if (part == 6 || part == 7) {
		c = (civ && !soldier) ? civ_helmet_col : helmet_col;
	} else if (part == 3) {
		c = soldier ? soldier_top * 0.8 : (civ ? (gend ? gend_cap : (farm ? farm_cap_c(dress) : civ_cap_c(dress))) : cap_col);
	} else if (part == 4) {
		c = pick(skin0, skin1, skin2, skin3, pal);
	} else if (part == 5) {
		c = (civ && skirt) ? (farm ? farm_cap_c(dress) : civ_cap_c(dress)) : pick(hair0, hair1, hair2, hair3, pal);
	} else if (part == 13) {
		c = civ ? (farm ? farm_leg_c(dress) : civ_leg_c(dress)) : c;
	}               // (parts 14 and 15, the pitchfork and the hoe, keep their own COLOR.rgb: ash handle, iron tines)
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
