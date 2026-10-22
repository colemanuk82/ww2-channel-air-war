"""Focke-Wulf Fw 200C Condor - published dimensions (four BMW/Bramo 323 radials), station tables.

Reference figures (see fw200.md for source URLs):
  length 23.45 m, span 32.85 m, height 6.30 m, wing area 119.85 m2, prop dia ~3.40 m, track ~6.8 m.
Long slender fuselage, single fin, big wings, four engines, twin-wheel main gear.

Built in metres, origin near the CG, nose toward +Y, up +Z (kit convention).
"""
import math
import bpy
import bmesh
from mathutils import Vector
import kit

TAU = math.pi * 2.0

REF = {
    "length":  23.45,
    "span":    32.85,
    "height":  6.30,
    "area":    119.85,
    "track":   6.80,
    "propdia": 3.40,
}


# ---------------------------------------------------------------- local helpers
def _aa(t, lo, hi):
    return lo + (hi - lo) * t


def wing(name, stations, n=24, camber=0.02, mirror=True):
    secs = []
    for (x, chord, yle, zle, th) in stations:
        ring = kit.airfoil_ring(th, camber, n)
        secs.append([(x, yle - chord * fx, zle + fz * chord) for (fx, fz) in ring])
    v, f = kit.loft(secs, True, True)
    if mirror:
        off = len(v)
        v.extend([(-x, y, z) for (x, y, z) in v[:off]])
        for face in list(f):
            f.append(tuple(off + i for i in reversed(face)))
    return kit.new_mesh_object(name, v, f)


def fin(name, xc, stations, n=16, camber=0.0, both=False):
    secs = []
    for (z, chord, yle, th) in stations:
        ring = kit.airfoil_ring(th, camber, n)
        secs.append([(xc + fz * chord, yle - chord * fx, z) for (fx, fz) in ring])
    v, f = kit.loft(secs, True, True)
    if both:
        off = len(v)
        v.extend([(-x, y, z) for (x, y, z) in v[:off]])
        for face in list(f):
            f.append(tuple(off + i for i in reversed(face)))
    return kit.new_mesh_object(name, v, f)


def nacelle(name, x, z, yf, length, r0, r1, n=22, bulge=1.0, ztop=0.95):
    secs = []
    S = 7
    for i in range(S + 1):
        t = i / S
        r = r0 + (r1 - r0) * t
        b = 1.0 + 0.08 * bulge * math.sin(math.pi * t)
        ring = kit.superellipse(n, r * b, r * b * ztop, 2.2)
        yy = yf - length * t
        secs.append([(x + px, yy, z + pz) for (px, pz) in ring])
    v, f = kit.loft(secs, True, True)
    return kit.new_mesh_object(name, v, f)


def prop(name, x, y, z, radius, blades=3, spinner_r=0.42, spin=0.0):
    p = kit.propeller(y, radius=radius, blades=blades, spinner_r=spinner_r,
                      blade_chord=0.32, spin=spin)
    p.name = name
    p.location = (x, y, z)
    grp = next((c for c in p.children if c.name == "Blades"), None)
    if grp is not None:
        for i, b in enumerate(sorted([c for c in grp.children if c.name.startswith("BladeTip")],
                                     key=lambda o: o.name)):
            th = TAU * i / blades
            b.rotation_euler = (math.radians(-90.0), th, 0.0)
            b.location = (math.sin(th) * (radius - 0.06), 0.0, math.cos(th) * (radius - 0.06))
        for i, b in enumerate(sorted([c for c in grp.children
                                      if c.name.startswith("Blade") and not c.name.startswith("BladeTip")],
                                     key=lambda o: o.name)):
            th = TAU * i / blades
            b.rotation_euler = (math.radians(-90.0), th, 0.0)
    return p


def subdiv(ob, cuts=2):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def _bbox(exclude_props):
    bpy.context.view_layer.update()
    xs, ys, zs = [], [], []
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        nm = ob.name
        if exclude_props and (nm.startswith("PropDisc") or nm.startswith("Blade") or nm.startswith("Spinner")):
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            xs.append(w.x); ys.append(w.y); zs.append(w.z)
    return (min(xs), max(xs)), (min(ys), max(ys)), (min(zs), max(zs))


def accuracy(id_):
    (ax0, ax1), (ay0, ay1), (az0, az1) = _bbox(True)
    (bx0, bx1), (by0, by1), (bz0, bz1) = _bbox(False)
    built = {"length": by1 - by0, "span": bx1 - bx0, "height": az1 - az0}
    parts, ok = [], True
    for ax in ("length", "span", "height"):
        b = built[ax]; r = REF[ax]
        d = (b - r) / r * 100.0
        good = abs(d) <= 2.0
        ok = ok and good
        parts.append("%s %.3f/%.3f m (%+.1f%%) %s" % (ax, b, r, d, "OK" if good else "FAIL"))
    print("ACCURACY %s %s -> %s" % (id_, " ".join(parts), "PASS" if ok else "FAIL"))
    return ok


# ---------------------------------------------------------------- airframe
NOSE = 12.10
TAIL = -11.35
HALF_SPAN = REF["span"] * 0.5

WING = [
    (0.000, 4.93, 0.00, 0.00, 0.160),
    (3.000, 4.82, -0.05, 0.10, 0.160),
    (6.000, 4.39, -0.20, 0.30, 0.160),
    (9.000, 3.74, -0.45, 0.62, 0.155),
    (12.000, 2.98, -0.80, 0.95, 0.150),
    (14.500, 2.06, -1.15, 1.25, 0.140),
    (15.800, 1.35, -1.40, 1.45, 0.130),
    (16.425, 0.87, -1.50, 1.55, 0.120),
]
WING_Y = 1.60
WING_Z = -0.35
NACELLE_X = (4.60, 9.20)


def _wing_le(x):
    for i in range(len(WING) - 1):
        a, b = WING[i], WING[i + 1]
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return _aa(t, a[2], b[2]), _aa(t, a[3], b[3])
    return WING[-1][2], WING[-1][3]


def build():
    fus = kit.tube("Fuselage", [
        (12.10, 0.14, 0.18, 0.05),
        (11.80, 0.28, 0.32, 0.05),
        (11.40, 0.44, 0.48, 0.04),
        (10.80, 0.58, 0.64, 0.03),
        (10.10, 0.68, 0.76, 0.02),
        (9.30, 0.76, 0.86, 0.01),      # flight deck
        (8.30, 0.82, 0.94, 0.00),
        (7.00, 0.85, 0.98, 0.00),
        (5.40, 0.85, 1.00, 0.00),      # long slender centre fuselage
        (3.60, 0.82, 0.98, 0.04),
        (1.80, 0.76, 0.92, 0.08),
        (0.00, 0.68, 0.84, 0.12),
        (-1.80, 0.58, 0.74, 0.16),
        (-3.60, 0.48, 0.64, 0.20),
        (-5.20, 0.38, 0.54, 0.24),
        (-6.80, 0.30, 0.44, 0.28),
        (-8.40, 0.22, 0.34, 0.32),
        (-9.80, 0.15, 0.24, 0.36),
        (-10.80, 0.09, 0.15, 0.38),
        (-11.35, 0.04, 0.07, 0.38),
    ], n=32, power=2.5)

    wg = wing("Wing", WING, n=24, camber=0.02, mirror=True)
    wg.location = (0.0, WING_Y, WING_Z)

    tp = wing("Tailplane", [
        (0.00, 3.40, 0.70, 0.00, 0.11),
        (1.90, 3.05, 0.55, 0.06, 0.105),
        (3.50, 2.30, 0.35, 0.13, 0.10),
        (4.50, 1.55, 0.20, 0.18, 0.10),
    ], n=16, camber=0.0, mirror=True)
    tp.location = (0.0, TAIL + 2.95, 0.70)

    fins = fin("Fin", 0.05, [
        (0.70, 3.60, 0.90, 0.12),
        (1.65, 3.10, 0.50, 0.11),
        (2.45, 2.20, 0.15, 0.10),
        (2.85, 1.35, -0.15, 0.10),
    ], n=18, both=False)
    fins.location = (0.0, TAIL + 2.70, 0.0)

    canopy = kit.canopy("Canopy", [
        (9.80, 0.62, 0.30, 0.70),
        (9.30, 0.72, 0.44, 0.84),
        (8.80, 0.72, 0.46, 0.86),
        (8.30, 0.62, 0.36, 0.82),
        (7.90, 0.46, 0.22, 0.74),
    ], n=16)
    # the long ventral gondola (gun turret / radar bay) under the rear fuselage
    kit.box("Gondola", (1.30, 5.20, 0.55), loc=(0.0, -0.60, -1.05))
    kit.turret("TurretDorsal", 0.0, 7.60, 0.92, 0.52, barrels=1, length=0.9)

    props = []
    for sx in (-1.0, 1.0):
        for j, nx in enumerate(NACELLE_X):
            yle, zle = _wing_le(nx)
            by = WING_Y + yle
            bz = WING_Z + zle + 0.06
            nacelle("Nacelle%d%d" % (int(sx), j), sx * nx, bz, by + 0.65, 3.60, 0.66, 0.44, n=22)
            props.append(prop("Propeller", sx * nx, by + 0.72, bz, REF["propdia"] * 0.5,
                              blades=3, spinner_r=0.42))
    for i, pp in enumerate(props):
        pp.name = "Propeller" if i == 0 else "Propeller%d" % (i + 1)

    eye = (0.0, 9.40, 0.96)          # above the deck (0.89), inside the canopy (1.32)
    pilot_grp = kit.pilot(eye)

    for nm, sx in (("GearL", 1.0), ("GearR", -1.0)):
        kit.gear_leg(nm, sx * REF["track"] * 0.5, WING_Y - 0.85, -0.80, 2.20, 0.45)
        kit.box("WheelOuter%d" % int(sx), (0.30, 0.30, 0.30),
                loc=(sx * (REF["track"] * 0.5 + 0.24), WING_Y - 0.85, -3.00))
    kit.gear_leg("TailWheel", 0.0, TAIL + 1.20, -0.85, 0.45, 0.19)

    dec = kit.markings("Luftwaffe", fus_x=0.82, fus_y=-2.20, fus_z=0.10, fus_r=0.55,
                       wing_y=WING_Y - 1.80, wing_span_x=11.00, wing_z=WING_Z + 0.55, wing_r=0.58,
                       fin_x=0.18, fin_y=TAIL + 2.45, fin_z=1.80, fin_r=0.38)

    body = kit.build_body([fus, wg, tp, fins, canopy])
    kit.empty("CockpitEye", eye)
    kit.empty("MuzzleL", (0.36, NOSE - 0.95, 0.12))
    kit.empty("MuzzleR", (-0.36, NOSE - 0.95, 0.12))

    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        if ob.name.startswith(("Fuselage", "Wing", "Tailplane", "Fin", "Canopy", "Nacelle")):
            subdiv(ob, cuts=2)

    accuracy("fw200")
