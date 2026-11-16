shader_type spatial;
render_mode cull_back;
// The moving farm props of scripts/ground/farm_people.gd: a led or driven horse and cart, a plough team, a Fordson
// tractor with its plough. One MultiMesh per prop type per tile; every instance walks the SAME beat as the man who
// leads / drives / follows it (the man is a figure of shaders/airfield_people.gdshader, kinds LEAD_HORSE, DRIVE_CART,
// PLOUGHMAN, spawned with exactly the same position, direction, beat length, speed and phase), so the pair stay rigid
// even through the turn at the end of the headland - the beat maths below is the figure shader's, line for line:
//   lap = 2 (len + halt * spd), d = mod(t * spd, lap), t = TIME + phase * 61, halt = 3.5 (figure kinds >= 10).
// INSTANCE_CUSTOM = (beat length in mesh metres, speed, phase 0..1, code); code = coat colour 0..3 + 4 * loaded.
// Mesh (metres, on the ground at y = 0, facing -Z): UV.x = limb (1 hind left, 2 fore left, 3 hind right, 4 fore right,
// 5 tail, 6 head and neck; +10 for the second horse of a plough team), UV.y = 1 for the part below the knee.
// COLOR.a * 10 = 1 horse coat (the instance's coat colour), 2 mane and tail, 4 the load on a cart (hay or sheaves, shown
// only when loaded), 0 its own COLOR.rgb. hz0 / hz1: the z of the first / second horse's centre (the legs and the head
// pivot about points relative to it).

uniform float hz0 = 0.0;
uniform float hz1 = 0.0;

varying vec3 v_col;

// turn p about the X axis through (y = py, z = pz): a positive angle swings a hanging limb forward (-Z)
vec3 rx2(vec3 p, float py, float pz, float a) {
	float c = cos(a);
	float s = sin(a);
	float y = p.y - py;
	float z = p.z - pz;
	return vec3(p.x, py + y * c - z * s, pz + y * s + z * c);
}

vec3 coat_of(int i) {
	if (i < 1) { return vec3(0.30, 0.17, 0.09); }      // bay
	if (i < 2) { return vec3(0.47, 0.26, 0.11); }      // chestnut
	if (i < 3) { return vec3(0.56, 0.56, 0.55); }      // grey
	return vec3(0.075, 0.07, 0.065);                   // black
}

vec3 mane_of(int i) {
	if (i < 1) { return vec3(0.04, 0.03, 0.025); }
	if (i < 2) { return vec3(0.74, 0.60, 0.36); }      // flaxen
	if (i < 3) { return vec3(0.30, 0.30, 0.30); }
	return vec3(0.035, 0.03, 0.03);
}

void vertex() {
	int limb_raw = int(UV.x + 0.5);
	bool second = limb_raw >= 10;
	int limb = second ? limb_raw - 10 : limb_raw;
	bool lower = UV.y > 0.5;
	int code = int(INSTANCE_CUSTOM.w + 0.5);
	bool loaded = code >= 4;
	int coat = loaded ? code - 4 : code;
	float ph = INSTANCE_CUSTOM.z;
	float t = TIME + ph * 61.0;
	// the beat (the figure shader's walk block)
	float halt = 3.5;
	float len = max(INSTANCE_CUSTOM.x, 0.5);
	float spd = max(INSTANCE_CUSTOM.y, 0.1);
	float pause = halt * spd;
	float lap = 2.0 * (len + pause);
	float d = mod(t * spd, lap);
	float w = 1.0;
	float adv = 0.0;
	float yaw = 0.0;
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
	w *= smoothstep(0.0, 0.5, min(adv, len - adv));
	float g = d * (TAU / 1.9);                 // the horse's stride: 1.9 m of ground per step cycle

	vec3 v = VERTEX;
	int part = int(COLOR.a * 10.0 + 0.5);
	float hz = second ? hz1 : hz0;
	if (part == 4 && !loaded) {
		v = vec3(0.0, 0.5, 0.0);               // no load: folded away to a degenerate point
	} else if (limb_raw > 0 && part != 4) {
		if (limb >= 1 && limb <= 4) {
			// the legs: the lateral walk, hind left, fore left, hind right, fore right, a quarter of a cycle apart
			float frac = (limb == 1) ? 0.0 : ((limb == 2) ? 0.25 : ((limb == 3) ? 0.5 : 0.75));
			float lz = hz + ((limb == 1 || limb == 3) ? 0.55 : -0.50);
			float pg = g + TAU * frac + (second ? 0.9 : 0.0);
			float th = 0.36 * sin(pg) * w;
			float kn = -0.62 * max(0.0, cos(pg)) * w;
			if (lower) {
				v = rx2(v, 0.52, lz, kn);
			}
			v = rx2(v, 1.05, lz, th);
		} else if (limb == 6) {
			v = rx2(v, 1.42, hz - 0.70, 0.07 * sin(g + 1.2 + (second ? 0.7 : 0.0)) * w);       // the head nods with the stride
		} else if (limb == 5) {
			v = rx2(v, 1.45, hz + 0.95, 0.22 * sin(t * 1.3 + (second ? 1.7 : 0.0)));            // the tail swishes
		}
	}
	// the horse's gait lifts and drops the whole body a little twice a stride; the tractor and carts just shake
	float bump = (limb_raw > 0 ? 0.022 * cos(2.0 * g) : 0.008 * sin(t * 9.0 + d * 3.0)) * w;
	v.y += bump;
	float cy = cos(yaw);
	float sy = sin(yaw);
	v = vec3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy);
	v.z -= adv;
	VERTEX = v;
	// (normals are left as built: the figure shader rotates them with the pose, a prop this small does not need it)
	NORMAL = normalize(vec3(NORMAL.x * cy + NORMAL.z * sy, NORMAL.y, -NORMAL.x * sy + NORMAL.z * cy));

	vec3 c = COLOR.rgb;
	if (part == 1) {
		c = coat_of(coat);
	} else if (part == 2) {
		c = mane_of(coat);
	}
	v_col = c;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.12;
}
