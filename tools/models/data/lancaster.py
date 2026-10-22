"""Avro Lancaster B.I - published dimensions (four Rolls-Royce Merlin XX), researched station tables.

Reference figures (see lancaster.md for source URLs):
  length 21.18 m, span 31.09 m, height 6.10 m, wing area 120.5 m2, track 7.24 m, prop dia 3.96 m.

Built in metres, origin near the CG, nose toward +Y, up +Z (kit convention).
"""
import math
import bpy
import bmesh
from mathutils import Vector
import kit

TAU = math.pi * 2.0

REF = {
    "length":  21.18,
    "span":    31.09,
    "height":  6.10,
    "area":    120.5,
    "track":   7.24,
    "propdia": 3.96,
}

# ---------------------------------------------------------------- local helpers
# The kit's data files may not be edited, so the multi-engine builders live here.


def _aa(t, lo, hi):
    return lo + (hi - lo) * t


def wing(name, stations, n=20, camber=0.02, mirror=True):
    """stations: (x, chord, y_le, z_le, thickness_ratio). Airfoil chord runs back from y_le."""
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


def fin(name, xc, stations, n=16, camber=0.0, both=True):
    """stations: (z, chord, y_le, thickness_ratio). Vertical surface, thickness along X, span along Z."""
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


def nacelle(name, x, z, yf, length, r0, r1, n=20, bulge=1.0):
    secs = []
    S = 6
    for i in range(S + 1):
        t = i / S
        r = r0 + (r1 - r0) * t
        b = 1.0 + 0.08 * bulge * math.sin(math.pi * t)
        ring = kit.superellipse(n, r * b, r * b * 0.94, 2.2)
        yy = yf - length * t
        secs.append([(x + px, yy, z + pz) for (px, pz) in ring])
    v, f = kit.loft(secs, True, True)
    return kit.new_mesh_object(name, v, f)


def prop(name, x, y, z, radius, blades=3, spinner_r=0.42, spin=0.0):
    """kit.propeller() leaves every blade drooping down the same axis; re-fan them around the prop axis."""
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
L = REF["length"]
NOSE = 10.00            # fuselage nose front (most +Y)
TAIL = -11.18           # rudder trailing edge (most -Y) -> 21.18 m overall
HALF_SPAN = REF["span"] * 0.5

# wing planform: (x, chord, y_le, z_le, thickness) - LE sweeps back, 5.5 deg dihedral
WING = [
    (0.00, 5.90, 0.60, 0.00, 0.180),
    (2.00, 5.80, 0.55, 0.06, 0.170),
    (4.50, 5.25, 0.30, 0.24, 0.160),
    (7.00, 4.30, -0.10, 0.50, 0.150),
    (9.50, 3.35, -0.60, 0.80, 0.140),
    (12.00, 2.40, -1.20, 1.10, 0.130),
    (14.00, 1.55, -1.70, 1.34, 0.120),
    (15.20, 1.05, -2.00, 1.48, 0.110),
    (15.55, 0.70, -2.15, 1.53, 0.100),
]
WING_Y = 6.60           # wing root leading-edge station (object shift in Y)
WING_Z = -0.02

NACELLE_X = (6.50, 11.30)


def _wing_le(x):
    for i in range(len(WING) - 1):
        a, b = WING[i], WING[i + 1]
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return _aa(t, a[2], b[2]), _aa(t, a[3], b[3])
    return WING[-1][2], WING[-1][3]


def build():
    # ---- fuselage
    fus = kit.tube("Fuselage", [
        (NOSE - 0.00, 0.13, 0.16, 0.04),
        (NOSE - 0.40, 0.30, 0.36, 0.04),
        (NOSE - 0.95, 0.45, 0.54, 0.02),      # bomb-aimer / nose glazing
        (NOSE - 1.60, 0.57, 0.68, 0.00),
        (NOSE - 2.30, 0.65, 0.80, 0.00),      # step up to the cockpit
        (NOSE - 3.00, 0.72, 0.92, 0.00),
        (NOSE - 3.70, 0.75, 0.98, 0.00),      # pilot / flight deck
        (NOSE - 4.60, 0.76, 1.00, 0.00),
        (NOSE - 5.80, 0.76, 1.00, 0.00),
        (NOSE - 7.20, 0.74, 0.98, 0.00),      # bomb bay
        (NOSE - 8.80, 0.70, 0.94, 0.00),
        (NOSE - 10.40, 0.64, 0.88, 0.02),
        (NOSE - 12.00, 0.56, 0.80, 0.05),
        (NOSE - 13.60, 0.48, 0.70, 0.08),
        (NOSE - 15.20, 0.38, 0.58, 0.12),
        (NOSE - 16.70, 0.29, 0.46, 0.16),
        (NOSE - 18.20, 0.21, 0.35, 0.20),
        (NOSE - 19.60, 0.14, 0.25, 0.24),
        (NOSE - 20.80, 0.09, 0.16, 0.26),
        (TAIL + 0.35, 0.045, 0.08, 0.26),
        (TAIL + 0.02, 0.018, 0.035, 0.26),
    ], n=32, power=2.5)

    # ---- wing: mid-wing, single lofted "Wing" object (both halves)
    wg = wing("Wing", WING, n=20, camber=0.02, mirror=True)
    wg.location = (0.0, WING_Y, WING_Z)

    # ---- tailplane + twin fins
    tail = wing("Tailplane", [
        (0.00, 3.05, 0.95, 0.00, 0.11),
        (1.80, 2.70, 0.80, 0.06, 0.105),
        (3.40, 2.10, 0.55, 0.14, 0.10),
        (4.40, 1.55, 0.35, 0.20, 0.095),
    ], n=16, camber=0.0, mirror=True)
    tail.location = (0.0, TAIL + 3.10, 0.42)

    fins = fin("Fin", 3.35, [
        (0.55, 2.65, 0.30, 0.12),
        (1.35, 2.30, 0.05, 0.11),
        (2.15, 1.75, -0.20, 0.10),
        (2.90, 1.05, -0.45, 0.10),
        (3.05, 0.70, -0.55, 0.10),
    ], n=16, both=True)
    fins.location = (0.0, TAIL + 2.85, 0.0)

    # ---- canopies: stepped nose glazing + flight-deck canopy
    nose_glass = kit.canopy("CanopyNose", [
        (NOSE - 0.55, 0.22, 0.24, 0.10),
        (NOSE - 0.95, 0.34, 0.36, 0.06),
        (NOSE - 1.45, 0.42, 0.44, 0.02),
        (NOSE - 1.95, 0.40, 0.42, 0.00),
    ], n=16)
    canopy = kit.canopy("Canopy", [
        (NOSE - 2.70, 0.55, 0.30, 0.72),
        (NOSE - 3.30, 0.62, 0.42, 0.86),
        (NOSE - 3.95, 0.62, 0.44, 0.90),
        (NOSE - 4.60, 0.55, 0.38, 0.86),
        (NOSE - 5.10, 0.40, 0.24, 0.78),
    ], n=16)

    # ---- bomb bay + dorsal turret + radiators
    kit.box("BombBay", (1.30, 7.20, 0.30), loc=(0.0, -1.60, -0.86))
    kit.turret("TurretDorsal", 0.0, 1.40, 0.86, 0.62, barrels=2, length=1.5)
    for sx in (-1.0, 1.0):
        kit.box("Radiator_%d" % int(sx), (0.42, 1.30, 0.30),
                loc=(sx * 6.50, WING_Y - 3.20, WING_Z - 0.95))

    # ---- engines: four nacelles, two per wing, + props
    props = []
    for sx in (-1.0, 1.0):
        for j, nx in enumerate(NACELLE_X):
            yle, zle = _wing_le(nx)
            by = WING_Y + yle
            bz = WING_Z + zle + 0.02
            nacelle("Nacelle%d%d" % (int(sx), j), sx * nx, bz, by + 0.55, 3.30, 0.66, 0.50, n=20)
            props.append(prop("Propeller", sx * nx, by + 0.72, bz, REF["propdia"] * 0.5,
                              blades=3, spinner_r=0.42))
    for i, pp in enumerate(props):
        pp.name = "Propeller" if i == 0 else "Propeller%d" % (i + 1)

    # ---- crew
    eye = (0.0, NOSE - 4.35, 1.07)   # above the deck (1.00), inside the canopy (1.34)
    pilot_grp = kit.pilot(eye)

    # ---- gear: main wheels into the inner nacelles + a fixed tail wheel
    gl = kit.gear_leg("GearL", REF["track"] * 0.5, WING_Y - 1.30, -0.72, 1.80, 0.55)
    gr = kit.gear_leg("GearR", -REF["track"] * 0.5, WING_Y - 1.30, -0.72, 1.80, 0.55)
    kit.gear_leg("TailWheel", 0.0, TAIL + 1.15, -0.95, 0.55, 0.24)

    dec = kit.markings("RAF", fus_x=0.74, fus_y=-2.20, fus_z=0.10, fus_r=0.48,
                       wing_y=WING_Y - 1.60, wing_span_x=10.20, wing_z=WING_Z + 0.90, wing_r=0.52,
                       fin_x=0.14, fin_y=TAIL + 3.40, fin_z=2.10, fin_r=0.42)

    body = kit.build_body([fus, wg, tail, fins, canopy, nose_glass])
    kit.empty("CockpitEye", eye)
    kit.empty("MuzzleL", (0.34, NOSE - 1.20, 0.32))
    kit.empty("MuzzleR", (-0.34, NOSE - 1.20, 0.32))

    # ---- high-poly refinement: subdivide the big lofted surfaces, keep props/decals light
    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        nm = ob.name
        if nm.startswith(("Fuselage", "Wing", "Tailplane", "Fin", "Canopy", "Nacelle")):
            subdiv(ob, cuts=2)

    accuracy("lancaster")
