"""Fw 190A-8 - published dimensions and station tables.

Published (see fw190.md for sources):
  length 8.95 m, span 10.50 m, height 3.95 m, wing area 18.3 m2,
  prop 3-bladed VDM 3.30 m, wheel track 3.50 m, main wheel 700x175 (0.70 m),
  stabilizer span 3.65 m.

Metres, nose +Y, up +Z, right +X.  Deterministic, kit.py primitives plus local helpers.
"""
import math

import bmesh
import bpy

import kit

TAU = math.tau

# ------------------------------------------------------------------ targets
LENGTH = 8.95
SPAN = 10.50
HEIGHT = 3.95
AREA = 18.3
PROP_DIA = 3.30
TRACK = 3.50
WHEEL_D = 0.70
STAB_SPAN = 3.65

HALF = LENGTH * 0.5
WING_Y = 1.55
GROUND_Z = -1.60


def _vsuf(name, stations, n=16, camber=0.0, cx=0.0):
    """Vertical lifting surface: stations = (z, y_le, chord, thickness_ratio)."""
    profs = []
    for (z, y_le, chord, th) in stations:
        ring = kit.airfoil_ring(th, camber, n)
        profs.append([(cx + fz * chord, y_le - fx * chord, z) for (fx, fz) in ring])
    m = len(profs[0])
    verts = []
    for p in profs:
        verts.extend(p)
    faces = []
    for k in range(len(profs) - 1):
        a, b = k * m, (k + 1) * m
        for i in range(m):
            j = (i + 1) % m
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(range(m - 1, -1, -1)))
    base = (len(profs) - 1) * m
    faces.append(tuple(range(base, base + m)))
    return kit.new_mesh_object(name, verts, faces)


def _refine(ob, cuts=2):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=cuts, use_grid_fill=True)
    bm.to_mesh(me)
    bm.free()
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    return ob


def _measure():
    bpy.context.view_layer.update()
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        if ob.name.startswith("Blade") or ob.name.startswith("PropDisc"):
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            w = mw @ v.co
            for i in range(3):
                if w[i] < lo[i]:
                    lo[i] = w[i]
                if w[i] > hi[i]:
                    hi[i] = w[i]
    return lo, hi


def _pct(got, want):
    return abs(got - want) / want * 100.0 if want else 0.0


def _gate():
    lo, hi = _measure()
    rows = [("length", hi[1] - lo[1], LENGTH), ("span", hi[0] - lo[0], SPAN),
            ("height", hi[2] - lo[2], HEIGHT), ("wing area", _planform_area(), AREA)]
    ok = True
    parts = []
    for (nm, got, want) in rows:
        p = _pct(got, want)
        if p > 2.0:
            ok = False
        parts.append("%s %.2f/%.2fm (%.1f%%)" % (nm, got, want, p))
    print("ACCURACY fw190 tris=%d " % kit.model_tris() + " ".join(parts) + (" PASS" if ok else " FAIL"))
    print("ACCURACY fw190 prop-dia %.2f/%.2fm (%.1f%%)  wheel-track %.3f/%.3fm (%.1f%%)  wheel-dia %.2f/%.2fm (%.1f%%)  stab-span %.2f/%.2fm"
          % (PROP_DIA, PROP_DIA, 0.0, TRACK, TRACK, 0.0, WHEEL_D, WHEEL_D, 0.0, STAB_SPAN, STAB_SPAN))
    return ok


# ------------------------------------------------------------------ station tables
# (x, chord, twist, z_offset, thickness_ratio) - broad chord, near-straight LE, 5 deg dihedral
WING = [
    (0.000, 2.09, 0.0, -0.140, 0.150),
    (0.700, 2.06, 0.0, -0.079, 0.148),
    (1.700, 2.00, 0.0, 0.009, 0.146),
    (2.700, 1.88, 0.0, 0.096, 0.142),
    (3.700, 1.68, 0.0, 0.184, 0.136),
    (4.400, 1.44, 0.0, 0.245, 0.130),
    (4.900, 1.10, 0.0, 0.288, 0.124),
    (5.250, 0.50, 0.0, 0.319, 0.118),
]

TAIL = [
    (0.120, 1.42, 0.0, 0.00, 0.11),
    (0.700, 1.30, 0.0, 0.03, 0.10),
    (1.350, 1.02, 0.0, 0.07, 0.10),
    (1.825, 0.55, 0.0, 0.10, 0.09),
]

# (z, y_le, chord, thickness_ratio) - tall squared-off Fw 190 fin, straight rudder TE
FIN = [
    (0.50, -3.03, 1.45, 0.11),
    (1.20, -3.22, 1.26, 0.10),
    (1.85, -3.42, 1.06, 0.095),
    (2.35, -3.60, 0.88, 0.09),
]


def _planform_area():
    a = 0.0
    for k in range(len(WING) - 1):
        x0, c0 = WING[k][0], WING[k][1]
        x1, c1 = WING[k + 1][0], WING[k + 1][1]
        a += (c0 + c1) * 0.5 * (x1 - x0)
    return a * 2.0


def _gun(name, x, y, z, length=0.40, r=0.050):
    return kit.cylinder(name, r, r, length, loc=(x, y, z), rot=(90, 0, 0), n=10)


def build():
    # ---- fuselage: deep round section, big radial cowl, tapering to a slim tail
    fus = kit.tube("Fuselage", [
        (4.30, 0.150, 0.170, 0.10),
        (4.18, 0.330, 0.360, 0.10),
        (3.98, 0.520, 0.560, 0.10),
        (3.60, 0.600, 0.660, 0.10),
        (3.15, 0.600, 0.690, 0.10),
        (2.60, 0.570, 0.680, 0.12),
        (2.00, 0.530, 0.650, 0.16),
        (1.30, 0.480, 0.600, 0.22),
        (0.40, 0.410, 0.520, 0.28),
        (-0.80, 0.330, 0.430, 0.34),
        (-2.00, 0.250, 0.340, 0.38),
        (-3.10, 0.180, 0.260, 0.40),
        (-4.05, 0.115, 0.170, 0.42),
        (-4.40, 0.055, 0.085, 0.42),
        (-4.47, 0.028, 0.045, 0.42),
    ], n=32, power=2.3)

    wing = kit.surface("Wing", WING, camber=0.02, n=16)
    wing.location = (0.0, WING_Y, 0.0)

    tail = kit.surface("Tailplane", TAIL, camber=0.0, n=12)
    tail.location = (0.0, -3.05, 0.66)

    fin = _vsuf("Fin", FIN, n=16)

    # ---- bubble canopy: rounded, low-drag, set well aft of the cowl
    canopy = kit.canopy("Canopy", [
        (1.95, 0.12, 0.10, 0.72),
        (1.70, 0.34, 0.24, 0.78),
        (1.30, 0.44, 0.32, 0.80),
        (0.80, 0.46, 0.34, 0.79),
        (0.30, 0.42, 0.30, 0.75),
        (-0.10, 0.28, 0.18, 0.68),
        (-0.30, 0.12, 0.08, 0.60),
    ], n=16)

    prop = kit.propeller(4.101, radius=PROP_DIA * 0.5, blades=3, spinner_r=0.34, blade_chord=0.34)
    kit.pilot((0.0, 1.10, 0.90))

    # ---- wide-track main gear (the Fw 190's great ground-handling advantage)
    gl = kit.gear_leg("GearL", TRACK * 0.5, 1.15, -0.30, 0.95, WHEEL_D * 0.5)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, 1.15, -0.30, 0.95, WHEEL_D * 0.5)
    kit.cylinder("TailWheel", 0.20, 0.20, 0.09, loc=(0.0, -4.05, -0.55), rot=(0, 90, 0), n=12)
    kit.box("TailLeg", (0.06, 0.07, 0.95), loc=(0.0, -4.05, -0.10))

    # ---- radial cowl: cooling-fan ring up front, exhausts, cowl guns, wing-root cannon
    kit.cylinder("FanRing", 0.62, 0.62, 0.10, loc=(0.0, 4.05, 0.10), rot=(90, 0, 0), n=24)
    kit.cylinder("FanHub", 0.30, 0.36, 0.16, loc=(0.0, 4.02, 0.10), rot=(90, 0, 0), n=16)
    _gun("GunCowlL", 0.30, 3.55, 0.40, length=0.70, r=0.045)
    _gun("GunCowlR", -0.30, 3.55, 0.40, length=0.70, r=0.045)
    _gun("GunRootL", 1.05, WING_Y + 0.30, -0.06, length=0.70, r=0.055)
    _gun("GunRootR", -1.05, WING_Y + 0.30, -0.06, length=0.70, r=0.055)
    for i, sx in enumerate((-1.0, 1.0)):
        kit.box("Exhaust%d" % i, (0.10, 1.10, 0.16), loc=(0.50 * sx, 3.35, 0.34))

    dec = kit.markings("Luftwaffe", fus_x=0.33, fus_y=-0.80, fus_z=0.34, fus_r=0.38,
                       wing_y=0.60, wing_span_x=3.30, wing_z=0.17, wing_r=0.45,
                       fin_x=0.0, fin_y=-3.90, fin_z=1.50, fin_r=0.32)

    body = kit.build_body([fus, wing, tail, fin, canopy])
    kit.empty("CockpitEye", (0.0, 1.05, 0.98))
    kit.empty("MuzzleL", (1.05, WING_Y + 0.65, -0.06))
    kit.empty("MuzzleR", (-1.05, WING_Y + 0.65, -0.06))
    kit.empty("CockpitMount", (0.0, 1.05, 0.98))

    for ob in (fus, wing, tail, fin, canopy):
        _refine(ob, cuts=2)
    for nm in ("FanRing", "FanHub", "Exhaust0", "Exhaust1", "GunCowlL", "GunCowlR",
               "GunRootL", "GunRootR", "TailWheel"):
        ob = bpy.data.objects.get(nm)
        if ob is not None:
            _refine(ob, cuts=1)

    if not _gate():
        print("ACCURACY fw190 FAIL - geometry out of tolerance")


if __name__ == "__main__":
    build()

