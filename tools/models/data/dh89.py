"""de Havilland DH.89 Dragon Rapide - a civil twin-engine biplane airliner, built from published figures.

Headline dimensions (sources in tools/models/data/dh89.md):
  length 10.52 m (34 ft 6 in)   wingspan 14.63 m (48 ft 0 in, upper wing)   height 3.12 m (10 ft 3 in, tail down)
  wing area 31.2 m2 (336 sq ft, both wings)   two de Havilland Gipsy Six 200 hp inverted in-line engines
  two-blade fixed-pitch propellers   fixed undercarriage with wheel spats   8 passengers, one pilot.
The lower-wing span, the chords and the interplane gap are not in the published tables: they are
scaled from the three-view and balanced so that both wings together give the published 31.2 m2.

Frame: metres, origin near the centre of gravity, nose toward +Y, up +Z, right +X (the glTF export maps
(x, y, z) -> (x, z, -y), so the nose lands on Godot's -Z). Deterministic - no RNG.
"""
import math

import bpy
from mathutils import Vector

import kit

ID = "dh89"
LEN = 10.52
SPAN = 14.63
HEIGHT = 3.12

NOSE_Y = 3.85
TAIL_Y = NOSE_Y - LEN                # -6.67  rudder trailing edge
HALF_U = SPAN * 0.5                  # 7.315 upper wing
HALF_L = 6.40                        # lower wing (scaled from the three-view)

Z_UP = 1.02                          # upper wing chord line (sits on short cabane struts above the cabin roof)
Z_LO = -0.50                         # lower wing chord line (at the cabin floor)
U_LE, U_C0, U_C1 = 1.10, 1.55, 0.95  # upper: leading edge at the root, root chord, tip chord
L_LE, L_C0, L_C1 = 0.80, 1.38, 0.76  # lower wing is set a little behind the upper (stagger)

NAC_X = 2.05                         # engine centrelines (on the lower wing leading edge)
NAC_FRONT = L_LE + 1.05
NAC_LEN = 2.60
ENG_Z = -0.46
PROP_R = 1.10
PROP_Y = NAC_FRONT + 0.20

WHEEL_R = 0.42
Z_GEAR = -0.62
TAIL_PLANE_HALF = 2.35
FIN_X = 1.55
EYE = (0.0, 2.45, 0.42)
N_WING = 22
CUTS = 1

EXPECT = (LEN, SPAN)
HEIGHT_INFO = HEIGHT


def _surf(name, sections, mirror=True):
    verts, faces = [], []
    m = len(sections[0])
    for s in sections:
        verts.extend(s)
    for k in range(len(sections) - 1):
        a, b = k * m, (k + 1) * m
        for i in range(m):
            j = (i + 1) % m
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(range(m - 1, -1, -1)))
    base = (len(sections) - 1) * m
    faces.append(tuple(range(base, base + m)))
    if mirror:
        off = len(verts)
        verts = verts + [(-x, y, z) for (x, y, z) in verts]
        for f in list(faces):
            faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _wing(name, half, le0, c0, c1, z0, sweep, dihedral, th, flat):
    """Tapered biplane wing half: constant chord over `flat` metres, then taper with a rounded tip."""
    xs = [0.0, flat * 0.5, flat, flat + (half - flat) * 0.25, flat + (half - flat) * 0.5,
          flat + (half - flat) * 0.75, half - 0.55, half - 0.25, half - 0.08, half]
    secs = []
    for x in xs:
        if x <= flat:
            c = c0
            le = le0
        else:
            t = (x - flat) / (half - flat)
            c = c0 + (c1 - c0) * t
            le = le0 - sweep * (x - flat)
        if x > half - 0.55:
            u = (x - (half - 0.55)) / 0.55
            c *= max(1.0 - 0.72 * u ** 2.0, 0.22)
            le -= 0.0
        z = z0 + dihedral * max(x - flat, 0.0)
        ring = kit.airfoil_ring(th, 0.035, N_WING)
        secs.append([(x, le - c * fx, z + c * fz) for (fx, fz) in ring])
    return _surf(name, secs)


def _nacelle(name, x, y_front, length, r0, r1, z_axis, n=20, stations=9):
    secs = []
    for i in range(stations):
        t = i / float(stations - 1)
        r = r0 + (r1 - r0) * t ** 0.9
        bulge = 1.0 + 0.06 * math.sin(math.pi * min(t * 1.4, 1.0))
        ring = kit.superellipse(n, max(r * bulge, 0.02), max(r * bulge * 0.92, 0.02), 2.3)
        secs.append([(x + px, y_front - length * t, z_axis + pz) for (px, pz) in ring])
    v, f = kit.loft(secs, True, True)
    return kit.new_mesh_object(name, v, f)


def _blade(name, r_hub, radius, chord, n=10, steps=6):
    secs = []
    for k in range(steps + 1):
        t = k / float(steps)
        r = r_hub + (radius - r_hub) * t
        c = chord * (1.0 - 0.22 * t)
        th = 0.12 - 0.04 * t
        pitch = math.radians(30.0 - 16.0 * t)
        cp, sp = math.cos(pitch), math.sin(pitch)
        ring = kit.airfoil_ring(th, 0.05, n)
        pts = []
        for (fx, fz) in ring:
            bx = (fx - 0.42) * c
            by = fz * c
            pts.append((bx * cp - by * sp, bx * sp + by * cp, r))
        secs.append(pts)
    return kit.new_mesh_object(name, *kit.loft(secs, True, True))


def _prop(name, suffix, x, y, z, radius, blades=2, spinner_r=0.17, blade_chord=0.24):
    prop = kit.empty(name, (x, y, z))
    sp = kit.cylinder("Spinner" + suffix, 0.06, spinner_r, spinner_r * 1.6, loc=(0, 0, 0), rot=(90, 0, 0), n=18)
    kit.parent_to(sp, prop)
    grp = kit.group("Blades" + suffix, (0.0, 0.0, 0.0), prop)
    dy = -0.34 * spinner_r
    for i in range(blades):
        a = kit.TAU * i / blades
        b = _blade("Blade%d%s" % (i, suffix), spinner_r * 0.5, radius, blade_chord)
        b.location = (0.0, dy, 0.0)
        b.rotation_euler = (0.0, a, 0.0)
        kit.parent_to(b, grp)
        tip = kit.box("BladeTip%d%s" % (i, suffix), (blade_chord * 0.7, 0.04, 0.10),
                      loc=(0.0, dy, radius - 0.06), rot=(0.0, math.degrees(a), 0.0))
        kit.parent_to(tip, grp)
    disc = kit.plate("PropDisc" + suffix, 0.0, radius, radius, n=28, thickness=0.02)
    disc.location = (0.0, dy, 0.0)
    kit.parent_to(disc, prop)
    return prop


def _min_z(exclude=()):
    bpy.context.view_layer.update()
    lo = 1e9
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or ob.name in exclude:
            continue
        mw = ob.matrix_world
        for c in ob.bound_box:
            lo = min(lo, (mw @ Vector(c)).z)
    return lo


def _set_top(ob, z_top):
    bpy.context.view_layer.update()
    mw = ob.matrix_world
    zs = [(mw @ Vector(c)).z for c in ob.bound_box]
    ob.location.z += (z_top - max(zs))


def _strut(name, x, y, z0, z1, w=0.07, d=0.16, lean=0.0):
    """A streamlined strut between two wings (a thin box leaning out by `lean` over its height)."""
    h = z1 - z0
    ob = kit.box(name, (w, d, math.sqrt(h * h + lean * lean)), loc=(x + lean * 0.5, y, (z0 + z1) * 0.5),
                 rot=(0, math.degrees(math.atan2(lean, h)) * -1.0, 0))
    return ob


def _accuracy():
    _lo, _hi, size = kit.bounds()
    checks = (("length", size[1], LEN), ("span", size[0], SPAN), ("height", size[2], HEIGHT))
    ok = True
    parts = []
    for nm, got, want in checks:
        pc = (got - want) / want * 100.0
        if abs(pc) > 2.0:
            ok = False
        parts.append("%s %.2f/%.2fm (%+.1f%%)" % (nm, got, want, pc))
    print("ACCURACY %-10s %s %s" % (ID, " ".join(parts), "PASS" if ok else "FAIL"))
    return ok


# fuselage: (y, half-width, half-height, section centre z). Plywood box section, cabin 1.22 m wide.
FUS = [
    (NOSE_Y, 0.20, 0.26, -0.18),
    (3.62, 0.36, 0.44, -0.10),
    (3.25, 0.50, 0.60, -0.04),
    (2.70, 0.59, 0.72, 0.00),
    (2.10, 0.62, 0.76, 0.00),
    (1.20, 0.63, 0.77, 0.00),
    (-0.50, 0.63, 0.77, 0.00),
    (-1.80, 0.62, 0.75, 0.01),
    (-2.80, 0.58, 0.70, 0.04),
    (-3.80, 0.48, 0.60, 0.10),
    (-4.80, 0.34, 0.46, 0.20),
    (-5.70, 0.20, 0.30, 0.30),
    (-6.30, 0.10, 0.17, 0.36),
    (TAIL_Y + 0.25, 0.05, 0.10, 0.38),
]

TAIL_ST = [
    (0.15, 1.20, 0.0, 0.0, 0.10, TAIL_Y + 1.28),
    (1.00, 1.10, 0.0, 0.0, 0.09, TAIL_Y + 1.18),
    (1.70, 0.95, 0.0, 0.0, 0.08, TAIL_Y + 1.02),
    (TAIL_PLANE_HALF, 0.55, 0.0, 0.0, 0.07, TAIL_Y + 0.66),
]

FIN_ST = [
    (0.00, 1.18, TAIL_Y + 1.28, 0.11),
    (0.30, 1.12, TAIL_Y + 1.20, 0.10),
    (0.60, 1.02, TAIL_Y + 1.08, 0.09),
    (0.85, 0.88, TAIL_Y + 0.92, 0.085),
    (1.05, 0.66, TAIL_Y + 0.70, 0.08),
    (1.17, 0.38, TAIL_Y + 0.42, 0.08),
]


def build():
    parts = []

    fus = kit.tube("Fuselage", FUS, n=36, power=3.0)
    parts.append(fus)

    # ---- the two wings, each a single mirrored mesh
    up = _wing("Wing", HALF_U, U_LE, U_C0, U_C1, Z_UP, 0.07, 0.0, 0.115, 2.4)
    lo = _wing("WingLower", HALF_L, L_LE, L_C0, L_C1, Z_LO, 0.07, 0.05, 0.12, 2.4)
    parts += [up, lo]

    # ---- struts: cabane pairs, then the N-type interplane struts out from each engine and from the outer panel
    for sx in (-1.0, 1.0):
        for (y, yy) in (("f", 0.95), ("r", -0.20)):
            parts.append(kit.box("StrutCabane%s%s" % (y, "L" if sx > 0 else "R"), (0.06, 0.11, 0.62),
                                 loc=(sx * 0.46, yy, 0.62), rot=(0, 0, 0)))
    for sx in (-1.0, 1.0):
        s = "L" if sx > 0 else "R"
        for k, (xs, ys_u, ys_l) in enumerate(((NAC_X, 0.55, 0.30), (4.55, 0.35, 0.10))):
            for (ya, yb, tag) in ((ys_u + 0.38, ys_l + 0.34, "F"), (ys_u - 0.30, ys_l - 0.36, "R")):
                z0 = Z_LO + 0.02
                z1 = Z_UP - 0.02
                parts.append(kit.box("StrutInterplane%d%s%s" % (k, tag, s), (0.065, 0.13, z1 - z0),
                                     loc=(sx * xs, (ya + yb) * 0.5, (z0 + z1) * 0.5)))

    # ---- engines: cowled Gipsy Six in a nacelle on each lower-wing leading edge
    for sx, sfx in ((1.0, ""), (-1.0, "R")):
        nac = _nacelle("Nacelle" + sfx, sx * NAC_X, NAC_FRONT, NAC_LEN, 0.30, 0.13, ENG_Z)
        parts.append(nac)
        parts.append(kit.box("Exhaust" + sfx, (0.07, 0.95, 0.07),
                             loc=(sx * (NAC_X + 0.30), NAC_FRONT - 1.05, ENG_Z - 0.10)))
        parts.append(kit.box("Intake" + sfx, (0.16, 0.30, 0.12), loc=(sx * NAC_X, NAC_FRONT - 0.95, ENG_Z - 0.30)))
    parts.append(_prop("Propeller", "", NAC_X, PROP_Y, ENG_Z, PROP_R))
    parts.append(_prop("PropellerR", "R", -NAC_X, PROP_Y, ENG_Z, PROP_R))

    # ---- tail: tailplane with a fin and rudder at each end (the Rapide's twin fins)
    tail = kit.surface("Tailplane", TAIL_ST, camber=0.0, n=14)
    tail.location = (0.0, 0.0, 0.36)
    parts.append(tail)
    fin_l = kit.fin("Fin", FIN_ST, camber=0.02, n=14)
    fin_l.location = (FIN_X, 0.0, 0.36)
    fin_r = kit.fin("FinR", FIN_ST, camber=0.02, n=14)
    fin_r.location = (-FIN_X, 0.0, 0.36)
    parts += [fin_l, fin_r]

    # ---- glazing: windscreen and side lights of the cockpit, then five square cabin windows each side
    CAN = [
        (3.50, 0.30, 0.10, 0.22),
        (3.25, 0.44, 0.17, 0.36),
        (2.95, 0.54, 0.22, 0.46),
        (2.60, 0.58, 0.22, 0.50),
        (2.25, 0.58, 0.18, 0.48),
    ]
    canopy = kit.canopy("Canopy", CAN, n=18)
    parts.append(canopy)
    frames = [kit.box("CanopyFrameTop", (0.88, 0.05, 0.05), loc=(0.0, 3.05, 0.70)),
              kit.box("WindscreenCentre", (0.05, 0.06, 0.30), loc=(0.0, 3.30, 0.52))]
    for sx in (-1.0, 1.0):
        s = "L" if sx > 0 else "R"
        for i in range(5):
            y = 1.55 - i * 0.62
            parts.append(kit.box("CanopyGlassWin%s%d" % (s, i), (0.03, 0.40, 0.34), loc=(sx * 0.635, y, 0.12)))
    parts.append(kit.box("DoorRear", (0.05, 0.62, 1.12), loc=(0.625, -3.00, -0.02)))

    # ---- undercarriage: mains under the engines, each in a streamlined spat; tail skid at the back
    z_ground = _min_z() - 0.05
    leg_len = Z_GEAR - z_ground - WHEEL_R
    for sx, nm in ((1.0, "GearL"), (-1.0, "GearR")):
        parts.append(kit.gear_leg(nm, sx * NAC_X, L_LE - 0.10, Z_GEAR, leg_len, WHEEL_R))
        spat = kit.tube("FairingSpat" + nm[-1], [(0.78, 0.01, 0.01, z_ground + WHEEL_R),
                                                  (0.55, 0.11, 0.30, z_ground + WHEEL_R + 0.06),
                                                  (0.0, 0.14, 0.46, z_ground + WHEEL_R + 0.10),
                                                  (-0.55, 0.11, 0.34, z_ground + WHEEL_R + 0.08),
                                                  (-0.95, 0.01, 0.02, z_ground + WHEEL_R)], n=14)
        spat.location = (sx * (NAC_X + 0.14), L_LE - 0.10, 0.0)
        parts.append(spat)
    parts.append(kit.tailwheel("TailWheel", -5.55, 0.05, strut=0.35, r=0.12))

    parts.append(kit.pilot(EYE))

    # ---- civil registration and livery stripe (decals)
    parts.append(kit.markings("Civil", fus_x=0.64, fus_y=-1.30, fus_z=0.10, fus_r=0.30,
                              wing_y=0.30, wing_span_x=5.0, wing_z=Z_UP + 0.10, wing_r=0.50,
                              fin_x=FIN_X, fin_y=TAIL_Y + 0.8, fin_z=0.80, fin_r=0.26))

    kit.build_body(parts)
    _set_top(fin_l, _min_z(exclude=("Fin", "FinR")) + HEIGHT)
    _set_top(fin_r, _min_z(exclude=("Fin", "FinR")) + HEIGHT)

    kit.refine_all(cuts=CUTS)
    for f in frames:
        kit.refine(f, 1)

    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (0.30, NOSE_Y - 0.4, -0.10))
    kit.empty("MuzzleR", (-0.30, NOSE_Y - 0.4, -0.10))
    _accuracy()
