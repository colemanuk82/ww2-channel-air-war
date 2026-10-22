"""Bristol Blenheim Mk IV - published dimensions (two Bristol Mercury XV), researched station tables.

Reference figures (see blenheim.md for source URLs):
  length 12.98 m, span 17.17 m, height 3.00 m, wing area 43.6 m2, prop dia 3.20 m, track ~4.80 m.

Built in metres, origin near the CG, nose toward +Y, up +Z (kit convention).
"""
import math
import bpy
import bmesh
from mathutils import Vector
import kit

TAU = math.pi * 2.0

REF = {
    "length":  12.98,
    "span":    17.17,
    "height":  3.00,
    "area":    43.6,
    "track":   4.80,
    "propdia": 3.20,
}


# ---------------------------------------------------------------- local helpers
def _aa(t, lo, hi):
    return lo + (hi - lo) * t


def wing(name, stations, n=22, camber=0.02, mirror=True):
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


def nacelle(name, x, z, yf, length, r0, r1, n=22, bulge=1.0):
    secs = []
    S = 7
    for i in range(S + 1):
        t = i / S
        r = r0 + (r1 - r0) * t
        b = 1.0 + 0.08 * bulge * math.sin(math.pi * t)
        ring = kit.superellipse(n, r * b, r * b * 0.95, 2.2)
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
    (ax0, ax1), (ay0, ay1), (az0, az1) = _bbox(True)     # airframe
    (bx0, bx1), (by0, by1), (bz0, bz1) = _bbox(False)    # everything incl. props
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
NOSE = 6.90
TAIL = -6.08
HALF_SPAN = REF["span"] * 0.5

WING = [
    (0.000, 3.48, 0.10, 0.00, 0.160),
    (1.500, 3.37, 0.05, 0.00, 0.150),
    (3.000, 3.08, -0.05, 0.02, 0.140),
    (4.500, 2.62, -0.20, 0.06, 0.135),
    (6.000, 2.11, -0.40, 0.12, 0.125),
    (7.200, 1.65, -0.60, 0.18, 0.115),
    (8.200, 1.20, -0.78, 0.24, 0.110),
    (8.585, 0.82, -0.88, 0.27, 0.100),
]
WING_Y = 2.30
WING_Z = -0.55
NACELLE_X = (2.55,)


def _wing_le(x):
    for i in range(len(WING) - 1):
        a, b = WING[i], WING[i + 1]
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return _aa(t, a[2], b[2]), _aa(t, a[3], b[3])
    return WING[-1][2], WING[-1][3]


def build():
    fus = kit.tube("Fuselage", [
        (6.90, 0.10, 0.13, -0.06),
        (6.60, 0.24, 0.26, -0.08),
        (6.25, 0.36, 0.34, -0.10),     # glazed bomb-aimer nose
        (5.80, 0.46, 0.44, -0.06),
        (5.30, 0.55, 0.56, 0.00),      # step up to the cockpit
        (4.70, 0.61, 0.64, 0.02),
        (4.00, 0.64, 0.68, 0.04),
        (3.10, 0.65, 0.70, 0.04),      # pilot
        (2.00, 0.63, 0.68, 0.04),
        (0.80, 0.58, 0.64, 0.05),
        (-0.60, 0.52, 0.58, 0.06),
        (-2.00, 0.44, 0.50, 0.08),
        (-3.30, 0.36, 0.42, 0.10),
        (-4.50, 0.28, 0.34, 0.12),
        (-5.40, 0.20, 0.26, 0.14),
        (-5.95, 0.12, 0.16, 0.15),
        (-6.08, 0.05, 0.07, 0.15),
    ], n=36, power=2.6)

    wg = wing("Wing", WING, n=26, camber=0.02, mirror=True)
    wg.location = (0.0, WING_Y, WING_Z)

    tp = wing("Tailplane", [
        (0.00, 2.45, 0.55, 0.00, 0.11),
        (1.20, 2.20, 0.45, 0.05, 0.105),
        (2.30, 1.70, 0.30, 0.10, 0.10),
        (3.05, 1.20, 0.18, 0.14, 0.10),
    ], n=18, camber=0.0, mirror=True)
    tp.location = (0.0, TAIL + 1.90, 0.42)

    fins = fin("Fin", 0.05, [
        (0.32, 2.30, 0.55, 0.12),
        (0.80, 2.00, 0.35, 0.11),
        (1.15, 1.45, 0.15, 0.10),
        (1.40, 0.90, 0.00, 0.10),
    ], n=20, both=False)
    fins.location = (0.0, TAIL + 1.75, 0.0)

    # stepped glazed nose (the Mk IV's signature long greenhouse) + cockpit canopy
    nose_glass = kit.canopy("CanopyNose", [
        (6.20, 0.26, 0.22, -0.06),
        (5.80, 0.40, 0.34, -0.04),
        (5.35, 0.48, 0.42, 0.02),
        (4.95, 0.44, 0.36, 0.10),
    ], n=16)
    canopy = kit.canopy("Canopy", [
        (5.05, 0.50, 0.28, 0.42),
        (4.60, 0.56, 0.36, 0.52),
        (4.10, 0.56, 0.36, 0.54),
        (3.60, 0.48, 0.30, 0.50),
        (3.20, 0.34, 0.18, 0.44),
    ], n=16)

    kit.turret("TurretDorsal", 0.0, 0.30, 0.74, 0.46, barrels=2, length=1.1)

    props = []
    for sx in (-1.0, 1.0):
        for j, nx in enumerate(NACELLE_X):
            yle, zle = _wing_le(nx)
            by = WING_Y + yle
            bz = WING_Z + zle + 0.05
            nacelle("Nacelle%d%d" % (int(sx), j), sx * nx, bz, by + 0.55, 2.70, 0.62, 0.46, n=26)
            props.append(prop("Propeller", sx * nx, by + 0.62, bz, REF["propdia"] * 0.5,
                              blades=3, spinner_r=0.40))
    for i, pp in enumerate(props):
        pp.name = "Propeller" if i == 0 else "Propeller%d" % (i + 1)

    eye = (0.0, 3.10, 0.81)          # above the fuselage deck (0.74 at this station), inside the canopy (0.87)
    pilot_grp = kit.pilot(eye)

    gl = kit.gear_leg("GearL", REF["track"] * 0.5, WING_Y - 0.60, -0.35, 0.85, 0.40)
    gr = kit.gear_leg("GearR", -REF["track"] * 0.5, WING_Y - 0.60, -0.35, 0.85, 0.40)
    kit.gear_leg("TailWheel", 0.0, TAIL + 1.05, -0.75, 0.45, 0.20)

    dec = kit.markings("RAF", fus_x=0.60, fus_y=-1.20, fus_z=0.10, fus_r=0.44,
                       wing_y=WING_Y - 1.20, wing_span_x=5.40, wing_z=WING_Z + 0.20, wing_r=0.46,
                       fin_x=0.07, fin_y=TAIL + 1.75, fin_z=0.95, fin_r=0.32)

    body = kit.build_body([fus, wg, tp, fins, canopy, nose_glass])
    kit.empty("CockpitEye", eye)
    kit.empty("MuzzleL", (0.28, NOSE - 1.05, -0.04))
    kit.empty("MuzzleR", (-0.28, NOSE - 1.05, -0.04))

    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        if ob.name.startswith(("Fuselage", "Wing", "Tailplane", "Fin", "Canopy", "Nacelle")):
            subdiv(ob, cuts=2)

    accuracy("blenheim")
