"""de Havilland Mosquito FB VI - published dimensions (two Merlin 25), researched station tables.

Reference figures (see mosquito.md for source URLs):
  length 12.55 m (over guns), span 16.51 m, height 4.65 m, wing area 41.81 m2, prop dia 3.81 m,
  track ~3.05 m. Smooth wooden fuselage, single fin, no turret, 4x20 mm in the belly.

Built in metres, origin near the CG, nose toward +Y, up +Z (kit convention).
"""
import math
import bpy
import bmesh
from mathutils import Vector
import kit

TAU = math.pi * 2.0

REF = {
    "length":  12.55,
    "span":    16.51,
    "height":  4.65,
    "area":    41.81,
    "track":   3.05,
    "propdia": 3.81,
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


def nacelle(name, x, z, yf, length, r0, r1, n=22, bulge=1.0, ztop=0.9):
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
NOSE = 6.35
TAIL = -6.20
HALF_SPAN = REF["span"] * 0.5

WING = [
    (0.000, 3.37, 0.05, 0.00, 0.150),
    (1.500, 3.26, 0.00, 0.05, 0.145),
    (3.000, 3.01, -0.10, 0.14, 0.140),
    (4.500, 2.60, -0.25, 0.24, 0.135),
    (6.000, 2.09, -0.45, 0.36, 0.125),
    (7.200, 1.58, -0.62, 0.46, 0.120),
    (8.000, 1.07, -0.76, 0.53, 0.110),
    (8.255, 0.73, -0.84, 0.57, 0.105),
]
WING_Y = 2.20
WING_Z = -0.15
NACELLE_X = (3.30,)


def _wing_le(x):
    for i in range(len(WING) - 1):
        a, b = WING[i], WING[i + 1]
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return _aa(t, a[2], b[2]), _aa(t, a[3], b[3])
    return WING[-1][2], WING[-1][3]


def build():
    fus = kit.tube("Fuselage", [
        (6.35, 0.16, 0.20, 0.05),      # solid FB VI nose
        (6.10, 0.30, 0.34, 0.05),
        (5.80, 0.42, 0.46, 0.04),
        (5.40, 0.50, 0.56, 0.03),
        (4.90, 0.55, 0.64, 0.02),
        (4.30, 0.57, 0.70, 0.02),
        (3.60, 0.57, 0.72, 0.02),      # cockpit (side by side)
        (2.40, 0.55, 0.70, 0.02),
        (1.00, 0.52, 0.66, 0.03),
        (-0.60, 0.46, 0.60, 0.05),
        (-2.20, 0.38, 0.50, 0.08),
        (-3.60, 0.30, 0.40, 0.12),
        (-4.80, 0.23, 0.31, 0.16),
        (-5.60, 0.16, 0.23, 0.20),
        (-6.00, 0.10, 0.15, 0.22),
        (-6.20, 0.04, 0.07, 0.22),
    ], n=38, power=2.4)

    wg = wing("Wing", WING, n=28, camber=0.02, mirror=True)
    wg.location = (0.0, WING_Y, WING_Z)

    tp = wing("Tailplane", [
        (0.00, 2.30, 0.55, 0.00, 0.10),
        (1.10, 2.05, 0.45, 0.05, 0.10),
        (2.10, 1.55, 0.30, 0.10, 0.095),
        (2.70, 1.05, 0.18, 0.14, 0.095),
    ], n=18, camber=0.0, mirror=True)
    tp.location = (0.0, TAIL + 1.85, 0.55)

    fins = fin("Fin", 0.05, [
        (0.60, 2.55, 0.45, 0.11),
        (1.35, 2.20, 0.20, 0.10),
        (1.95, 1.60, 0.00, 0.10),
        (2.35, 0.95, -0.20, 0.10),
    ], n=20, both=False)
    fins.location = (0.0, TAIL + 2.10, 0.0)

    # one-piece blown cockpit canopy (the Mosquito has no separate nose glazing)
    canopy = kit.canopy("Canopy", [
        (4.10, 0.46, 0.30, 0.52),
        (3.60, 0.56, 0.42, 0.62),
        (3.00, 0.58, 0.44, 0.64),
        (2.40, 0.50, 0.36, 0.60),
        (1.95, 0.34, 0.22, 0.52),
    ], n=16)

    # the 20 mm belly cannon pack + bomb-bay fairing
    kit.box("CannonPack", (0.62, 1.30, 0.30), loc=(0.0, NOSE - 0.55, -0.42))

    props = []
    for sx in (-1.0, 1.0):
        for j, nx in enumerate(NACELLE_X):
            yle, zle = _wing_le(nx)
            by = WING_Y + yle
            bz = WING_Z + zle + 0.05
            nacelle("Nacelle%d%d" % (int(sx), j), sx * nx, bz, by + 0.60, 3.05, 0.62, 0.42, n=28, ztop=1.0)
            props.append(prop("Propeller", sx * nx, by + 0.68, bz, REF["propdia"] * 0.5,
                              blades=3, spinner_r=0.42))
    for i, pp in enumerate(props):
        pp.name = "Propeller" if i == 0 else "Propeller%d" % (i + 1)

    eye = (0.0, 3.30, 0.81)          # above the deck (0.74), inside the canopy (1.08)
    pilot_grp = kit.pilot(eye)

    gl = kit.gear_leg("GearL", REF["track"] * 0.5, WING_Y - 0.55, -0.30, 1.55, 0.45)
    gr = kit.gear_leg("GearR", -REF["track"] * 0.5, WING_Y - 0.55, -0.30, 1.55, 0.45)
    kit.gear_leg("TailWheel", 0.0, TAIL + 1.00, -0.70, 0.40, 0.18)

    dec = kit.markings("RAF", fus_x=0.53, fus_y=-0.80, fus_z=0.10, fus_r=0.42,
                       wing_y=WING_Y - 1.00, wing_span_x=5.20, wing_z=WING_Z + 0.24, wing_r=0.44,
                       fin_x=0.07, fin_y=TAIL + 1.95, fin_z=1.55, fin_r=0.30)

    body = kit.build_body([fus, wg, tp, fins, canopy])
    kit.empty("CockpitEye", eye)
    kit.empty("MuzzleL", (0.16, NOSE - 0.30, -0.40))
    kit.empty("MuzzleR", (-0.16, NOSE - 0.30, -0.40))

    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        if ob.name.startswith(("Fuselage", "Wing", "Tailplane", "Fin", "Canopy", "Nacelle")):
            subdiv(ob, cuts=2)

    accuracy("mosquito")
