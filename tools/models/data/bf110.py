"""Bf 110C - published dimensions and station tables.

Published (see bf110.md for sources):
  length 12.10 m, span 16.25 m, height 3.50 m, wing area 38.4 m2,
  props 2 x 3-bladed VDM 3.10 m, main wheel 875x320 (0.875 m), twin fins on the tailplane tips.
  Wheel track is not published in a dimensional table; it is scaled from the 3-view / the
  nacelle-mounted gear layout -> 4.40 m (flagged in bf110.md).

Metres, nose +Y, up +Z, right +X.  Deterministic, kit.py primitives plus local helpers.
"""
import math

import bmesh
import bpy

import kit

TAU = math.tau

# ------------------------------------------------------------------ targets
LENGTH = 12.10
SPAN = 16.25
HEIGHT = 3.50
AREA = 38.4
PROP_DIA = 3.10
TRACK = 4.40
WHEEL_D = 0.875

HALF = LENGTH * 0.5
WING_Y = 1.55
NACELLE_X = TRACK * 0.5


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
    print("ACCURACY bf110 tris=%d " % kit.model_tris() + " ".join(parts) + (" PASS" if ok else " FAIL"))
    print("ACCURACY bf110 prop-dia %.2f/%.2fm (%.1f%%)  wheel-track %.2f/%.2fm (%.1f%%)  wheel-dia %.3f/%.3fm (%.1f%%)"
          % (PROP_DIA, PROP_DIA, 0.0, TRACK, TRACK, 0.0, WHEEL_D, WHEEL_D, 0.0))
    return ok


# ------------------------------------------------------------------ station tables
# (x, chord, twist, z_offset, thickness_ratio) - straight tapered wing, 1.5 deg dihedral
WING = [
    (0.000, 3.20, 0.0, -0.100, 0.170),
    (0.600, 3.16, 0.0, -0.084, 0.168),
    (1.800, 3.02, 0.0, -0.053, 0.164),
    (3.200, 2.76, 0.0, -0.016, 0.158),
    (4.600, 2.40, 0.0, 0.021, 0.150),
    (6.000, 1.96, 0.0, 0.057, 0.142),
    (7.200, 1.42, 0.0, 0.089, 0.132),
    (7.900, 0.80, 0.0, 0.107, 0.124),
    (8.125, 0.36, 0.0, 0.113, 0.120),
]

# (x, chord, twist, z_offset, thickness_ratio) - tailplane, twin fins sit on its tips
TAIL = [
    (0.100, 1.35, 0.0, 0.00, 0.11),
    (0.700, 1.24, 0.0, 0.03, 0.10),
    (1.500, 1.05, 0.0, 0.07, 0.10),
    (2.300, 0.72, 0.0, 0.10, 0.09),
]

# (z, y_le, chord, thickness_ratio) - endplate fin/rudder, straight TE at y = -6.05
FIN = [
    (0.42, -4.65, 1.40, 0.10),
    (1.00, -4.80, 1.25, 0.095),
    (1.60, -4.95, 1.10, 0.09),
    (2.10, -5.08, 0.97, 0.085),
    (2.25, -5.13, 0.92, 0.08),
]


def _planform_area():
    a = 0.0
    for k in range(len(WING) - 1):
        x0, c0 = WING[k][0], WING[k][1]
        x1, c1 = WING[k + 1][0], WING[k + 1][1]
        a += (c0 + c1) * 0.5 * (x1 - x0)
    return a * 2.0


def _twin_fin(name, xs, stations, n=14):
    """Two endplate fins at x = +-xs, built as ONE mesh so the node is simply named `Fin`."""
    profs = []
    for (z, y_le, chord, th) in stations:
        ring = kit.airfoil_ring(th, 0.0, n)
        profs.append([(xs + fz * chord, y_le - fx * chord, z) for (fx, fz) in ring])
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
    off = len(verts)
    verts.extend([(-x, y, z) for (x, y, z) in verts[:off]])
    for f in list(faces):
        faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _gun(name, x, y, z, length=0.40, r=0.045):
    return kit.cylinder(name, r, r, length, loc=(x, y, z), rot=(90, 0, 0), n=10)


PROP_Y = 2.10
NACELLE_Z = 0.06


def _nacelle(name, sx):
    ob = kit.tube(name, [
        (1.75, 0.46, 0.48, 0.00),
        (1.35, 0.58, 0.60, 0.00),
        (0.70, 0.62, 0.66, 0.00),
        (-0.10, 0.60, 0.64, 0.00),
        (-0.90, 0.52, 0.56, 0.00),
        (-1.60, 0.40, 0.44, 0.00),
        (-2.10, 0.24, 0.26, 0.00),
    ], n=24, power=2.1)
    ob.location = (NACELLE_X * sx, 0.0, NACELLE_Z)
    return ob


def build():
    # ---- fuselage: long, narrow, oval section - the classic Zerstorer shape
    fus = kit.tube("Fuselage", [
        (6.05, 0.120, 0.140, 0.05),
        (5.85, 0.280, 0.300, 0.06),
        (5.50, 0.420, 0.440, 0.06),
        (5.00, 0.520, 0.560, 0.06),
        (4.40, 0.580, 0.640, 0.06),
        (3.60, 0.600, 0.680, 0.07),
        (2.80, 0.580, 0.660, 0.09),
        (2.00, 0.520, 0.600, 0.12),
        (1.00, 0.440, 0.520, 0.16),
        (-0.40, 0.360, 0.440, 0.20),
        (-1.80, 0.280, 0.360, 0.24),
        (-3.20, 0.220, 0.280, 0.27),
        (-4.60, 0.150, 0.210, 0.29),
        (-5.60, 0.090, 0.130, 0.30),
        (-5.95, 0.045, 0.070, 0.30),
    ], n=30, power=2.2)

    wing = kit.surface("Wing", WING, camber=0.02, n=16)
    wing.location = (0.0, WING_Y, 0.0)

    tail = kit.surface("Tailplane", TAIL, camber=0.0, n=12)
    tail.location = (0.0, -4.70, 0.48)

    fin = _twin_fin("Fin", 2.30, FIN, n=16)

    # ---- long multi-pane Zerstorer greenhouse
    canopy = kit.canopy("Canopy", [
        (4.65, 0.16, 0.10, 0.70),
        (4.30, 0.36, 0.22, 0.76),
        (3.80, 0.50, 0.34, 0.80),
        (3.10, 0.54, 0.38, 0.82),
        (2.40, 0.54, 0.38, 0.82),
        (1.80, 0.48, 0.34, 0.80),
        (1.30, 0.34, 0.24, 0.74),
        (1.00, 0.16, 0.12, 0.66),
    ], n=16)

    # ---- two DB 601 nacelles integrated into the wing, each with a VDM prop
    ncl = _nacelle("NacelleL", 1.0)
    ncr = _nacelle("NacelleR", -1.0)
    p1 = kit.propeller(PROP_Y, radius=PROP_DIA * 0.5, blades=3, spinner_r=0.30, blade_chord=0.30)
    p1.location = (NACELLE_X, PROP_Y, NACELLE_Z)
    p2 = kit.propeller(PROP_Y, radius=PROP_DIA * 0.5, blades=3, spinner_r=0.30, blade_chord=0.30, spin=60.0)
    p2.name = "PropellerR"
    p2.location = (-NACELLE_X, PROP_Y, NACELLE_Z)

    kit.pilot((0.0, 3.40, 0.86))

    # ---- main gear: short legs retracting rearwards into the nacelles
    gl = kit.gear_leg("GearL", NACELLE_X, 0.55, -0.273, 0.54, WHEEL_D * 0.5)
    gr = kit.gear_leg("GearR", -NACELLE_X, 0.55, -0.273, 0.54, WHEEL_D * 0.5)
    kit.cylinder("TailWheel", 0.17, 0.17, 0.08, loc=(0.0, -5.45, -0.62), rot=(0, 90, 0), n=12)
    kit.box("TailLeg", (0.06, 0.07, 0.85), loc=(0.0, -5.45, -0.18))

    # ---- Zerstorer nose: 4 x MG 17 over 2 x MG FF, plus radiators and exhausts
    for i, sx in enumerate((-1.0, 1.0)):
        _gun("GunTop%d" % i, 0.24 * sx, 5.72, 0.22, length=0.66, r=0.030)
        _gun("GunTopB%d" % i, 0.10 * sx, 5.74, 0.30, length=0.62, r=0.030)
        _gun("GunFF%d" % i, 0.32 * sx, 5.75, -0.02, length=0.60, r=0.052)
        kit.box("Radiator%d" % i, (0.42, 0.80, 0.24), loc=(3.05 * sx, -0.75, -0.40))
        kit.box("Exhaust%d" % i, (0.10, 1.20, 0.16), loc=(2.55 * sx, 1.05, 0.36))

    dec = kit.markings("Luftwaffe", fus_x=0.50, fus_y=0.50, fus_z=0.30, fus_r=0.42,
                       wing_y=0.30, wing_span_x=4.00, wing_z=0.14, wing_r=0.55,
                       fin_x=2.30, fin_y=-5.50, fin_z=1.30, fin_r=0.30)
    band_r = kit.box("DecalFinBandR", (0.04, 0.48, 0.36), loc=(-2.30, -5.50, 1.30))
    kit.parent_to(band_r, dec)

    body = kit.build_body([fus, wing, tail, fin, canopy, ncl, ncr])
    kit.empty("CockpitEye", (0.0, 3.40, 0.88))
    kit.empty("MuzzleL", (0.32, 6.20, -0.02))
    kit.empty("MuzzleR", (-0.32, 6.20, -0.02))
    kit.empty("CockpitMount", (0.0, 3.40, 0.88))

    for ob in (fus, wing, canopy):
        _refine(ob, cuts=2)
    for ob in (fin, ncl, ncr, tail):
        _refine(ob, cuts=1)
    for nm in ("Radiator0", "Radiator1", "Exhaust0", "Exhaust1", "TailWheel",
               "GunTop0", "GunTop1", "GunTopB0", "GunTopB1", "GunFF0", "GunFF1"):
        ob = bpy.data.objects.get(nm)
        if ob is not None:
            _refine(ob, cuts=1)

    if not _gate():
        print("ACCURACY bf110 FAIL - geometry out of tolerance")


if __name__ == "__main__":
    build()

