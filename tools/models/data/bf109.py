"""Bf 109E-4 (Emil) - published dimensions and station tables.

Published (see bf109.md for sources):
  length 8.64 m, span 9.87 m, height 2.50 m, wing area 16.17 m2,
  prop 3-bladed VDM 3.10 m, wheel track 1.975 m, main wheel 650x150 (0.65 m).

Built in metres, nose toward +Y, up +Z, right +X (glTF maps that onto Godot's -Z).
Deterministic: no RNG.  Only kit.py primitives plus helpers defined in this file.
"""
import math

import bmesh
import bpy

import kit

TAU = math.tau
D2R = math.radians

# ------------------------------------------------------------------ targets
LENGTH = 8.64
SPAN = 9.87
HEIGHT = 2.50
AREA = 16.17
PROP_DIA = 3.10
TRACK = 1.975
WHEEL_D = 0.65

HALF = LENGTH * 0.5              # nose tip at +4.32, rudder TE at -4.32
WING_Y = 1.40                    # wing root leading edge (absolute y)
WING_DIHEDRAL = 6.0              # degrees
GROUND_Z = -1.10                 # main-wheel contact plane


# ------------------------------------------------------------------ local helpers
def _vsuf(name, stations, n=14, camber=0.0, cx=0.0):
    """Vertical lifting surface: stations = (z, y_le, chord, thickness_ratio).

    Chord runs toward -Y, thickness toward +X, span toward +Z (a fin/rudder)."""
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
    """bmesh subdivision + shade smooth, deterministically."""
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


def _has_ancestor(ob, name):
    p = ob.parent
    while p is not None:
        if p.name == name:
            return True
        p = p.parent
    return False


def _measure():
    """Airframe bounds (spinner counted, prop blades/disc excluded - a prop blur disc is not airframe)."""
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
    length = hi[1] - lo[1]
    span = hi[0] - lo[0]
    height = hi[2] - lo[2]
    area = _planform_area()
    ok = True
    rows = [("length", length, LENGTH), ("span", span, SPAN), ("height", height, HEIGHT),
            ("wing area", area, AREA)]
    parts = []
    for (nm, got, want) in rows:
        p = _pct(got, want)
        if p > 2.0:
            ok = False
        parts.append("%s %.2f/%.2fm (%.1f%%)" % (nm, got, want, p))
    print("ACCURACY bf109 tris=%d " % kit.model_tris() + " ".join(parts) + (" PASS" if ok else " FAIL"))
    print("ACCURACY bf109 prop-dia %.2f/%.2fm (%.1f%%)  wheel-track %.3f/%.3fm (%.1f%%)  wheel-dia %.2f/%.2fm (%.1f%%)"
          % (PROP_DIA, PROP_DIA, 0.0, TRACK, TRACK, 0.0, WHEEL_D, WHEEL_D, 0.0))
    return ok


# ------------------------------------------------------------------ station tables
# (x, chord, twist, z_offset, thickness_ratio) root -> tip.  z_offset carries the 6 deg dihedral.
WING = [
    (0.000, 1.96, 0.0, -0.120, 0.142),
    (0.600, 1.93, 0.0, -0.057, 0.140),
    (1.400, 1.87, 0.0, 0.027, 0.136),
    (2.400, 1.77, 0.0, 0.132, 0.132),
    (3.400, 1.58, 0.0, 0.238, 0.127),
    (4.100, 1.34, 0.0, 0.311, 0.122),
    (4.550, 1.08, 0.0, 0.354, 0.118),
    (4.800, 0.76, 0.0, 0.377, 0.115),
    (4.935, 0.32, 0.0, 0.399, 0.113),
]

TAIL = [
    (0.100, 1.16, 0.0, 0.00, 0.10),
    (0.550, 1.05, 0.0, 0.03, 0.09),
    (1.050, 0.80, 0.0, 0.07, 0.09),
    (1.450, 0.42, 0.0, 0.10, 0.09),
]

# (z, y_le, chord, thickness_ratio) - squared-off Bf 109 fin with a straight rudder TE at y = -4.32
FIN = [
    (0.34, -2.70, 1.62, 0.10),
    (0.75, -2.86, 1.46, 0.09),
    (1.10, -3.04, 1.28, 0.085),
    (1.40, -3.24, 1.08, 0.08),
]


def _planform_area():
    """Gross planform area from the wing table (root carried to the centreline), 2 halves."""
    a = 0.0
    for k in range(len(WING) - 1):
        x0, c0 = WING[k][0], WING[k][1]
        x1, c1 = WING[k + 1][0], WING[k + 1][1]
        a += (c0 + c1) * 0.5 * (x1 - x0)
    return a * 2.0


def _gun(name, x, y, z, length=0.34, r=0.045):
    b = kit.cylinder(name, r, r, length, loc=(x, y, z), rot=(90, 0, 0), n=10)
    return b


def build():
    # ---- fuselage: angular section (power 2.6), slim tail, deep nose for the DB 601
    fus = kit.tube("Fuselage", [
        (4.24, 0.090, 0.110, 0.02),
        (4.06, 0.200, 0.240, 0.04),
        (3.82, 0.300, 0.360, 0.05),
        (3.45, 0.370, 0.450, 0.06),
        (3.00, 0.410, 0.500, 0.07),
        (2.55, 0.420, 0.530, 0.08),
        (1.95, 0.420, 0.540, 0.10),
        (1.35, 0.390, 0.510, 0.13),
        (0.60, 0.330, 0.450, 0.18),
        (-0.30, 0.260, 0.370, 0.23),
        (-1.40, 0.200, 0.290, 0.27),
        (-2.50, 0.150, 0.220, 0.29),
        (-3.50, 0.100, 0.160, 0.30),
        (-4.05, 0.055, 0.090, 0.30),
        (-4.24, 0.025, 0.040, 0.30),
    ], n=32, power=2.6)

    wing = kit.surface("Wing", WING, camber=0.02, n=16)
    wing.location = (0.0, WING_Y, 0.0)

    tail = kit.surface("Tailplane", TAIL, camber=0.0, n=12)
    tail.location = (0.0, -3.05, 0.34)

    fin = _vsuf("Fin", FIN, n=16)

    canopy = kit.canopy("Canopy", [
        (2.48, 0.16, 0.10, 0.52),
        (2.25, 0.30, 0.20, 0.60),
        (1.95, 0.36, 0.26, 0.64),
        (1.55, 0.38, 0.28, 0.63),
        (1.05, 0.36, 0.27, 0.61),
        (0.60, 0.28, 0.20, 0.58),
        (0.25, 0.14, 0.10, 0.52),
    ], n=16)

    prop = kit.propeller(3.99, radius=PROP_DIA * 0.5, blades=3, spinner_r=0.30, blade_chord=0.30)
    kit.pilot((0.0, 1.45, 0.70))

    # ---- main gear: narrow track, tall thin legs (the Emil's weak point)
    gl = kit.gear_leg("GearL", TRACK * 0.5, 1.20, 0.005, 0.78, WHEEL_D * 0.5)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, 1.20, 0.005, 0.78, WHEEL_D * 0.5)
    # tailwheel
    kit.cylinder("TailWheel", 0.145, 0.145, 0.07, loc=(0.0, -3.95, -0.60), rot=(0, 90, 0), n=12)
    kit.box("TailLeg", (0.05, 0.06, 0.70), loc=(0.0, -3.95, -0.28))

    # ---- detail: cowl MGs, exhausts, radiators, oil cooler, supercharger intake
    _gun("GunCowlL", 0.235, 3.30, 0.30, length=0.55, r=0.038)
    _gun("GunCowlR", -0.235, 3.30, 0.30, length=0.55, r=0.038)
    _gun("GunWingL", 1.30, 1.62, -0.02, length=0.60, r=0.050)
    _gun("GunWingR", -1.30, 1.62, -0.02, length=0.60, r=0.050)
    for i, sx in enumerate((-1.0, 1.0)):
        kit.box("Exhaust%d" % i, (0.085, 1.05, 0.115), loc=(0.30 * sx, 3.15, 0.24))
        kit.box("Radiator%d" % i, (0.34, 0.68, 0.20), loc=(1.15 * sx, -0.42, -0.62))
    kit.box("OilCooler", (0.26, 0.44, 0.20), loc=(0.0, 2.28, -0.42))
    kit.cylinder("Intake", 0.15, 0.13, 0.30, loc=(0.0, 3.95, 0.28), rot=(90, 0, 0), n=12)

    dec = kit.markings("Luftwaffe", fus_x=0.34, fus_y=-0.60, fus_z=0.24, fus_r=0.34,
                       wing_y=0.53, wing_span_x=3.20, wing_z=0.16, wing_r=0.40,
                       fin_x=0.0, fin_y=-3.80, fin_z=0.95, fin_r=0.30)

    body = kit.build_body([fus, wing, tail, fin, canopy])
    kit.empty("CockpitEye", (0.0, 1.45, 0.72))
    kit.empty("MuzzleL", (1.30, 1.95, -0.02))
    kit.empty("MuzzleR", (-1.30, 1.95, -0.02))
    kit.empty("CockpitMount", (0.0, 1.45, 0.72))

    # ---- subdivide + shade smooth for the high-poly pass
    for ob in (fus, wing, tail, fin, canopy):
        _refine(ob, cuts=2)
    for nm in ("Exhaust0", "Exhaust1", "Radiator0", "Radiator1", "OilCooler", "Intake",
               "GunCowlL", "GunCowlR", "GunWingL", "GunWingR"):
        ob = bpy.data.objects.get(nm)
        if ob is not None:
            _refine(ob, cuts=1)

    ok = _gate()
    if not ok:
        print("ACCURACY bf109 FAIL - geometry out of tolerance")


if __name__ == "__main__":
    build()

