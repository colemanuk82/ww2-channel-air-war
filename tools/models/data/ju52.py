"""Junkers Ju 52/3m - published dimensions (three BMW 132 radials, one in the nose), station tables.

Reference figures (see ju52.md for source URLs):
  length 18.90 m, span 29.20 m, height 5.55 m, wing area 110.5 m2, prop dia 3.26 m, track ~4.6 m.
Corrugated duralumin skin, fixed spatted main gear, single fin, one engine in the nose.

Built in metres, origin near the CG, nose toward +Y, up +Z (kit convention).
"""
import math
import bpy
import bmesh
from mathutils import Vector
import kit

TAU = math.pi * 2.0

REF = {
    "length":  18.90,
    "span":    29.25,
    "height":  5.55,
    "area":    110.5,
    "track":   4.60,
    "propdia": 3.26,
}


# ---------------------------------------------------------------- local helpers
def _aa(t, lo, hi):
    return lo + (hi - lo) * t


def ctube(name, stations, n=32, power=2.6, ripple=0.020, waves=16):
    """A corrugated fuselage: the rounded section rippled around the circumference (Junkers skin)."""
    secs = []
    for (y, hw, hh, cz) in stations:
        ring = []
        for i in range(n):
            a = TAU * i / n
            c, s = math.cos(a), math.sin(a)
            x = math.copysign(abs(c) ** (2.0 / power), c) * max(hw, 0.01)
            z = math.copysign(abs(s) ** (2.0 / power), s) * max(hh, 0.01)
            k = 1.0 + ripple * math.cos(waves * a)
            ring.append((x * k, y, cz + z * k))
        secs.append(ring)
    v, f = kit.loft(secs, True, True)
    return kit.new_mesh_object(name, v, f)


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


def prop(name, x, y, z, radius, blades=3, spinner_r=0.40, spin=0.0):
    p = kit.propeller(y, radius=radius, blades=blades, spinner_r=spinner_r,
                      blade_chord=0.30, spin=spin)
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
COWL_FRONT = 9.05
TAIL = -9.36
NOSE_PROP_Y = 9.10          # spinner front = 9.10 + 1.1*0.40 = 9.54 -> 9.54 + 9.36 = 18.90 m
HALF_SPAN = REF["span"] * 0.5

WING = [
    (0.000, 4.58, 0.00, 0.00, 0.160),
    (3.000, 4.52, -0.10, 0.10, 0.160),
    (6.000, 4.37, -0.30, 0.30, 0.160),
    (9.000, 3.94, -0.60, 0.55, 0.155),
    (11.500, 3.26, -0.95, 0.82, 0.150),
    (13.000, 2.42, -1.20, 1.03, 0.140),
    (13.800, 1.53, -1.35, 1.16, 0.130),
    (14.625, 0.89, -1.46, 1.26, 0.120),
]
WING_Y = 1.30
WING_Z = -0.35
NACELLE_X = (5.60,)


def _wing_le(x):
    for i in range(len(WING) - 1):
        a, b = WING[i], WING[i + 1]
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return _aa(t, a[2], b[2]), _aa(t, a[3], b[3])
    return WING[-1][2], WING[-1][3]


def build():
    fus = ctube("Fuselage", [
        (8.60, 0.34, 0.38, 0.05),      # fire wall / behind the nose cowl
        (8.30, 0.58, 0.58, 0.04),
        (7.80, 0.72, 0.72, 0.03),
        (7.20, 0.80, 0.82, 0.02),      # cockpit
        (6.30, 0.84, 0.90, 0.01),
        (5.20, 0.86, 0.95, 0.00),      # max section (cabin)
        (3.60, 0.86, 0.96, 0.00),
        (2.00, 0.84, 0.94, 0.02),
        (0.40, 0.80, 0.90, 0.05),
        (-1.20, 0.74, 0.84, 0.08),
        (-2.80, 0.66, 0.76, 0.12),
        (-4.40, 0.56, 0.66, 0.16),
        (-6.00, 0.46, 0.56, 0.20),
        (-7.40, 0.36, 0.46, 0.24),
        (-8.50, 0.26, 0.35, 0.28),
        (-9.10, 0.16, 0.24, 0.30),
        (-9.36, 0.06, 0.10, 0.30),
    ], n=34, power=2.6, ripple=0.020, waves=16)

    wg = wing("Wing", WING, n=26, camber=0.02, mirror=True)
    wg.location = (0.0, WING_Y, WING_Z)

    tp = wing("Tailplane", [
        (0.00, 2.85, 0.60, 0.00, 0.10),
        (1.60, 2.55, 0.45, 0.06, 0.10),
        (3.00, 1.90, 0.28, 0.13, 0.095),
        (3.80, 1.30, 0.15, 0.18, 0.095),
    ], n=16, camber=0.0, mirror=True)
    tp.location = (0.0, TAIL + 2.50, 0.55)

    fins = fin("Fin", 0.05, [
        (0.50, 3.30, 0.70, 0.12),
        (1.35, 2.90, 0.35, 0.11),
        (2.05, 2.10, 0.05, 0.10),
        (2.60, 1.30, -0.20, 0.10),
    ], n=18, both=False)
    fins.location = (0.0, TAIL + 2.60, 0.0)

    # the fuselage nose is a full engine cowl (corrugated centre engine)
    nacelle("NoseCowl", 0.0, 0.10, COWL_FRONT, 1.60, 0.62, 0.66, n=22, ztop=0.95)
    canopy = kit.canopy("Canopy", [
        (7.70, 0.58, 0.26, 0.72),
        (7.20, 0.66, 0.38, 0.84),
        (6.70, 0.66, 0.40, 0.86),
        (6.20, 0.58, 0.32, 0.82),
        (5.85, 0.42, 0.20, 0.74),
    ], n=16)
    kit.turret("TurretDorsal", 0.0, 4.20, 0.90, 0.46, barrels=1, length=0.9)

    props = []
    # nose engine
    props.append(prop("Propeller", 0.0, NOSE_PROP_Y, 0.10, REF["propdia"] * 0.5,
                      blades=3, spinner_r=0.40))
    # two wing engines
    for sx in (-1.0, 1.0):
        for j, nx in enumerate(NACELLE_X):
            yle, zle = _wing_le(nx)
            by = WING_Y + yle
            bz = WING_Z + zle + 0.06
            nacelle("Nacelle%d%d" % (int(sx), j), sx * nx, bz, by + 0.60, 3.10, 0.60, 0.44, n=22)
            pnm = "Propeller2" if sx > 0 else "Propeller3"
            props.append(prop(pnm, sx * nx, by + 0.66, bz, REF["propdia"] * 0.5,
                              blades=3, spinner_r=0.38))

    eye = (0.0, 6.95, 0.96)          # above the deck (0.885), inside the canopy (1.26)
    pilot_grp = kit.pilot(eye)

    # fixed, spatted main gear
    for nm, sx in (("GearL", 1.0), ("GearR", -1.0)):
        kit.gear_leg(nm, sx * REF["track"] * 0.5, WING_Y - 0.55, -0.55, 1.85, 0.55)
        kit.box("Spat%d" % int(sx), (0.46, 1.30, 0.95),
                loc=(sx * REF["track"] * 0.5, WING_Y - 0.55, -2.35))
    kit.gear_leg("TailWheel", 0.0, TAIL + 1.10, -0.70, 0.42, 0.18)

    dec = kit.markings("Luftwaffe", fus_x=0.82, fus_y=-1.40, fus_z=0.10, fus_r=0.55,
                       wing_y=WING_Y - 1.60, wing_span_x=8.60, wing_z=WING_Z + 0.40, wing_r=0.55,
                       fin_x=0.16, fin_y=TAIL + 2.20, fin_z=1.70, fin_r=0.36)

    body = kit.build_body([fus, wg, tp, fins, canopy])
    kit.empty("CockpitEye", eye)
    kit.empty("MuzzleL", (0.45, 8.60, 0.55))
    kit.empty("MuzzleR", (-0.45, 8.60, 0.55))

    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        if ob.name.startswith(("Fuselage", "Wing", "Tailplane", "Fin", "Canopy", "Nacelle", "NoseCowl")):
            subdiv(ob, cuts=2)

    accuracy("ju52")
