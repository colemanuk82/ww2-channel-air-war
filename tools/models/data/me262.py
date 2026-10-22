"""Me 262A-1a (Schwalbe) - published dimensions and station tables.

Published (see me262.md for sources):
  length 10.60 m, span 12.60 m, height 3.50 m, wing area 21.7 m2,
  wing leading-edge sweep 18.5 deg, Jumo 004B nacelle (engine 0.76 m dia x 3.50 m long),
  nosewheel 660x160 (0.66 m), main wheel 840x300 (0.84 m), tricycle gear.
  Main-wheel track is not in a published table; scaled from the 3-view -> 2.30 m (flagged in me262.md).

No propeller: the contract `Propeller` node is an Empty at the nose (spin axis, nothing to draw).
Metres, nose +Y, up +Z, right +X.  Deterministic, kit.py primitives plus local helpers.
"""
import math

import bmesh
import bpy

import kit

TAU = math.tau

# ------------------------------------------------------------------ targets
LENGTH = 10.60
SPAN = 12.60
HEIGHT = 3.50
AREA = 21.7
SWEEP = 18.5
TRACK = 2.30
NOSE_WHEEL_D = 0.66
MAIN_WHEEL_D = 0.84

HALF = LENGTH * 0.5
NACELLE_X = 1.85
NACELLE_Z = -0.62


def _swept(name, stations, sweep_deg, camber=0.02, n=16, mirror=True):
    """Horizontal half wing: stations = (x, chord, twist, z_offset, thickness_ratio).

    The leading edge is raked back by `sweep_deg` (kit.surface can only build unswept panels)."""
    t = math.tan(math.radians(sweep_deg))
    profs = []
    for (x, chord, _tw, zoff, th) in stations:
        ring = kit.airfoil_ring(th, camber, n)
        yle = -x * t
        profs.append([(x, yle - fx * chord, zoff + fz * chord) for (fx, fz) in ring])
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
    if mirror:
        off = len(verts)
        verts.extend([(-x, y, z) for (x, y, z) in verts[:off]])
        for f in list(faces):
            faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _vsuf(name, stations, n=16, camber=0.0, cx=0.0):
    """Vertical fin: stations = (z, y_le, chord, thickness_ratio)."""
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
    print("ACCURACY me262 tris=%d " % kit.model_tris() + " ".join(parts) + (" PASS" if ok else " FAIL"))
    print("ACCURACY me262 wheel-track %.2f/%.2fm (%.1f%%)  main-wheel %.2f/%.2fm (%.1f%%)  nose-wheel %.2f/%.2fm (%.1f%%)  sweep %0.1f/%.1f deg"
          % (TRACK, TRACK, 0.0, MAIN_WHEEL_D, MAIN_WHEEL_D, 0.0, NOSE_WHEEL_D, NOSE_WHEEL_D, 0.0, SWEEP, SWEEP))
    return ok


# ------------------------------------------------------------------ station tables
WING = [
    (0.000, 2.27, 0.0, -0.050, 0.128),
    (0.600, 2.20, 0.0, -0.047, 0.127),
    (1.600, 2.09, 0.0, -0.040, 0.125),
    (2.600, 1.93, 0.0, -0.032, 0.122),
    (3.600, 1.75, 0.0, -0.025, 0.118),
    (4.600, 1.51, 0.0, -0.017, 0.112),
    (5.400, 1.20, 0.0, -0.011, 0.106),
    (5.950, 0.85, 0.0, -0.007, 0.100),
    (6.300, 0.44, 0.0, -0.004, 0.096),
]

TAIL = [
    (0.120, 1.20, 0.0, 0.00, 0.11),
    (0.700, 1.10, 0.0, 0.02, 0.105),
    (1.400, 0.92, 0.0, 0.05, 0.10),
    (2.050, 0.62, 0.0, 0.08, 0.09),
]

# (z, y_le, chord, thickness_ratio) - tall swept Me 262 fin, rudder TE at y = -5.30
FIN = [
    (0.45, -3.75, 1.55, 0.11),
    (1.05, -3.92, 1.38, 0.10),
    (1.60, -4.08, 1.22, 0.095),
    (2.05, -4.22, 1.08, 0.09),
    (2.15, -4.25, 1.05, 0.085),
]


def _planform_area():
    a = 0.0
    for k in range(len(WING) - 1):
        x0, c0 = WING[k][0], WING[k][1]
        x1, c1 = WING[k + 1][0], WING[k + 1][1]
        a += (c0 + c1) * 0.5 * (x1 - x0)
    return a * 2.0


def _jet(sx):
    """One Jumo 004 nacelle: outer tube + intake lip + inner duct + compressor face + exhaust cone."""
    x = NACELLE_X * sx
    f = 1.0 if sx > 0 else -1.0
    outer = kit.tube("NacelleL" if sx > 0 else "NacelleR", [
        (0.55, 0.42, 0.42, 0.00),
        (0.35, 0.44, 0.44, 0.00),
        (-0.20, 0.46, 0.46, 0.00),
        (-1.20, 0.45, 0.45, 0.00),
        (-2.20, 0.43, 0.43, 0.00),
        (-2.85, 0.40, 0.40, 0.00),
    ], n=26, power=2.0)
    outer.location = (x, 0.0, NACELLE_Z)
    lip = kit.cylinder("IntakeLipL" if sx > 0 else "IntakeLipR", 0.48, 0.48, 0.12,
                       loc=(x, 0.56, NACELLE_Z), rot=(90, 0, 0), n=26)
    duct = kit.cylinder("IntakeL" if sx > 0 else "IntakeR", 0.34, 0.34, 0.60,
                        loc=(x, 0.30, NACELLE_Z), rot=(90, 0, 0), n=22)
    face = kit.cylinder("CompressorL" if sx > 0 else "CompressorR", 0.33, 0.33, 0.10,
                        loc=(x, 0.02, NACELLE_Z), rot=(90, 0, 0), n=22)
    nozzle = kit.tube("NozzleL" if sx > 0 else "NozzleR", [
        (-2.80, 0.41, 0.41, 0.00),
        (-3.05, 0.38, 0.38, 0.00),
        (-3.30, 0.30, 0.30, 0.00),
    ], n=22, power=2.0)
    nozzle.location = (x, 0.0, NACELLE_Z)
    zw = kit.cylinder("ZwiebelL" if sx > 0 else "ZwiebelR", 0.20, 0.05, 0.36,
                      loc=(x, -3.38, NACELLE_Z), rot=(90, 0, 0), n=16)
    pylon = kit.box("PylonL" if sx > 0 else "PylonR", (0.16, 1.05, 0.52),
                    loc=(x, -0.55, NACELLE_Z + 0.52))
    return [outer, lip, duct, face, nozzle, zw, pylon]


def _gun(name, x, y, z, length=0.40, r=0.045):
    return kit.cylinder(name, r, r, length, loc=(x, y, z), rot=(90, 0, 0), n=10)


def build():
    # ---- fuselage: smooth oval tube, deepest at the cockpit, long tapering tail
    fus = kit.tube("Fuselage", [
        (5.30, 0.100, 0.120, 0.02),
        (5.10, 0.240, 0.260, 0.04),
        (4.80, 0.360, 0.400, 0.05),
        (4.40, 0.460, 0.520, 0.06),
        (3.90, 0.520, 0.600, 0.07),
        (3.30, 0.560, 0.660, 0.08),
        (2.60, 0.580, 0.700, 0.09),
        (1.80, 0.580, 0.700, 0.10),
        (1.00, 0.540, 0.640, 0.12),
        (0.00, 0.480, 0.580, 0.14),
        (-1.20, 0.400, 0.480, 0.17),
        (-2.40, 0.320, 0.380, 0.19),
        (-3.60, 0.240, 0.300, 0.21),
        (-4.60, 0.160, 0.210, 0.22),
        (-5.15, 0.090, 0.120, 0.22),
        (-5.30, 0.040, 0.060, 0.22),
    ], n=32, power=2.1)

    wing = _swept("Wing", WING, SWEEP, camber=0.02, n=16)
    wing.location = (0.0, 1.05, 0.0)

    tail = _swept("Tailplane", TAIL, 9.0, camber=0.0, n=12)
    tail.location = (0.0, -4.05, 0.28)

    fin = _vsuf("Fin", FIN, n=16)

    # ---- low, streamlined bubble canopy set over the wing root
    canopy = kit.canopy("Canopy", [
        (3.75, 0.14, 0.10, 0.62),
        (3.45, 0.34, 0.22, 0.70),
        (3.05, 0.44, 0.30, 0.74),
        (2.55, 0.45, 0.31, 0.74),
        (2.05, 0.40, 0.26, 0.70),
        (1.70, 0.28, 0.16, 0.62),
        (1.45, 0.12, 0.08, 0.54),
    ], n=16)

    kit.pilot((0.0, 2.90, 0.80))

    # ---- twin Jumo 004 nacelles under the wings
    for sx in (1.0, -1.0):
        _jet(sx)

    # ---- tricycle gear (nose gear is an extra node; the contract uses GearL/GearR)
    gl = kit.gear_leg("GearL", TRACK * 0.5, 0.15, -0.30, 0.63, MAIN_WHEEL_D * 0.5)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, 0.15, -0.30, 0.63, MAIN_WHEEL_D * 0.5)
    gn = kit.gear_leg("GearN", 0.0, 3.40, -0.52, 0.50, NOSE_WHEEL_D * 0.5)

    # ---- nose battery: 4 x MK 108, muzzles flush with the nose cone
    for i, sx in enumerate((-1.0, 1.0)):
        _gun("GunLow%d" % i, 0.26 * sx, 5.10, -0.04, length=0.40, r=0.034)
        _gun("GunUp%d" % i, 0.14 * sx, 5.10, 0.16, length=0.40, r=0.034)
        kit.box("Slat%d" % i, (0.10, 1.55, 0.05), loc=(5.55 * sx, -0.90, 0.03))

    # new-style paint: no swastika anywhere - kit.markings substitutes a plain fin band
    dec = kit.markings("Luftwaffe", fus_x=0.50, fus_y=0.80, fus_z=0.20, fus_r=0.45,
                       wing_y=-1.84, wing_span_x=4.20, wing_z=0.08, wing_r=0.55,
                       fin_x=0.0, fin_y=-4.60, fin_z=1.30, fin_r=0.32)

    parts = [fus, wing, tail, fin, canopy]
    parts += [bpy.data.objects[n] for n in
              ("NacelleL", "NacelleR", "NozzleL", "NozzleR")]
    body = kit.build_body(parts)
    kit.empty("CockpitEye", (0.0, 2.90, 0.86))      # above the deck (0.79), inside the canopy (1.05)
    kit.empty("MuzzleL", (0.26, 5.34, -0.04))
    kit.empty("MuzzleR", (-0.26, 5.34, -0.04))
    kit.empty("CockpitMount", (0.0, 2.90, 0.86))
    # no propeller on a jet: an Empty carries the (unused) contract node at the nose
    kit.empty("Propeller", (0.0, 5.20, 0.02))

    # ---- high-poly pass: bmesh subdivision + shade smooth
    for ob in [fus, wing, tail, fin, canopy] + \
              [bpy.data.objects[n] for n in ("NacelleL", "NacelleR", "NozzleL", "NozzleR")]:
        _refine(ob, cuts=2)
    for nm in ("IntakeLipL", "IntakeLipR", "IntakeL", "IntakeR", "CompressorL", "CompressorR",
               "ZwiebelL", "ZwiebelR"):
        _refine(bpy.data.objects[nm], cuts=1)

    if not _gate():
        print("ACCURACY me262 FAIL - geometry out of tolerance")


if __name__ == "__main__":
    build()

