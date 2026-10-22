"""Lockheed P-38J Lightning - 1:1 airframe from published figures.

Published: length 11.53 m (37 ft 10 in), span 15.85 m (52 ft 0 in), height 3.91 m (12 ft 10 in,
on gear), wing area 30.43 m2 (327.5 sq ft), near-rectangular wing, twin tail booms + central
nacelle, tricycle gear (nose wheel forward, no tail wheel), 3-blade Curtiss Electric props
3.51 m (11 ft 6 in) dia, counter-rotating (handed).  Main wheel 0.914 m (36 in) dia, nose
0.686 m (27 in).  Figures + sources: tools/models/data/p38.md

Frame: origin at the CG station, nose toward +Y, up +Z, right +X.  Original geometry only.
"""
import math

import bpy
import kit

ID = "p38"
LEN = 11.53
SPAN = 15.85
HEIGHT = 3.91
AREA = 30.43

HALF = SPAN * 0.5
ROOT_CHORD = 2.30
TIP_CHORD = 1.54                    # P-38 wing is very nearly constant-chord
DIHEDRAL = 3.5
SWEEP = 0.0                         # straight leading edge
WING_LE = 0.90
NOSE = WING_LE + 3.25               # central-nacelle gun nose
TAIL = NOSE - LEN
BOOM_X = 2.52                       # boom centreline: published main-gear track 5.03 m (16 ft 6 in)
SPINNER_R = 0.40
PROP_R = 1.755                      # 11 ft 6 in / 2
PROP_PITCH = 22.0                   # blade twist; the two props are handed (+/-)
WHEEL_R = 0.457                     # 36 in main tyre
NOSE_WHEEL_R = 0.343                # 27 in nose tyre
TRACK = BOOM_X * 2.0
EYE = (0.0, -0.55, 0.72)

N_FUS = 30
N_BOOM = 30
N_WING = 26
N_TAIL = 20
N_FIN = 20
N_CAN = 22
CUTS = 1

NACELLE_TAIL = NOSE - 6.30          # central nacelle ends just behind the wing trailing edge


def _surface(name, sections, mirror=True):
    verts, faces = kit.loft(sections, True, True)
    if mirror:
        off = len(verts)
        verts = verts + [(-x, y, z) for (x, y, z) in verts]
        for f in list(faces):
            faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _ring(xs, chord, yle, zoff, th, camber=0.03, n=12):
    ring = kit.airfoil_ring(th, camber, n)
    return [(xs, yle - chord * fx, zoff + fz * chord) for (fx, fz) in ring]


def _descendants(ob):
    out, stack = [], list(ob.children)
    while stack:
        c = stack.pop()
        out.append(c)
        stack.extend(c.children)
    return out


def _handed_prop(name, x, nose_y, radius, spinner_r, blade_chord, hand):
    """A 3-blade prop pitched about its own span; `hand` (+1/-1) sets the pitch sense so the two
    engines counter-rotate.  The primary keeps the kit node names ('Propeller' > Blades/Spinner/
    PropDisc); the secondary is renamed 'Propeller2' with unique child names."""
    p = kit.propeller(nose_y, radius=radius, blades=3, spinner_r=spinner_r,
                      blade_chord=blade_chord, spin=0.0)
    p.name = name
    p.location = (x, nose_y, 0.0)
    sign = 1.0 if hand > 0 else -1.0
    for d in _descendants(p):
        if d.type == 'MESH' and d.name.startswith("Blade") and not d.name.startswith("BladeTip"):
            a = d.rotation_euler.z
            d.rotation_mode = 'YXZ'
            d.rotation_euler = (math.radians(90.0), math.radians(sign * PROP_PITCH), a)
    if name != "Propeller":
        for d in _descendants(p):
            if d.name == "Blades":
                d.name = "Blades2"
            elif d.name.startswith("PropDisc"):
                d.name = "PropDisc2"
            elif d.name.startswith("Spinner"):
                d.name = "Spinner2"
            elif d.name.startswith("BladeTip"):
                d.name = "BladeTip2_%s" % d.name[len("BladeTip"):]
            elif d.name.startswith("Blade"):
                d.name = "PropBlade2_%s" % d.name[len("Blade"):]
    return p


def _z_max():
    from mathutils import Vector
    hi = -1e9
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            hi = max(hi, (ob.matrix_world @ Vector(c)).z)
    return hi


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
    print("ACCURACY %-8s %s %s" % (ID, " ".join(parts), "PASS" if ok else "FAIL"))
    return ok


def build():
    # -------------------------------------------------------------- central nacelle (fuselage)
    fus = kit.tube("Fuselage", [
        (NOSE, 0.10, 0.11, 0.00),           # gun nose
        (NOSE - 0.30, 0.23, 0.25, 0.00),
        (NOSE - 0.75, 0.33, 0.37, 0.00),    # gun bay
        (NOSE - 1.40, 0.41, 0.45, 0.02),
        (NOSE - 2.20, 0.44, 0.51, 0.04),    # cockpit
        (NOSE - 3.00, 0.44, 0.53, 0.07),
        (NOSE - 3.85, 0.42, 0.51, 0.10),
        (NOSE - 4.70, 0.34, 0.43, 0.13),
        (NOSE - 5.55, 0.24, 0.31, 0.15),
        (NACELLE_TAIL, 0.12, 0.16, 0.16),
    ], n=N_FUS, power=2.4)

    # -------------------------------------------------------------- wing (near-rectangular)
    xs_list = [0.30, 0.90, 1.70, 2.50, 3.30, 4.10, 4.90, 5.70, 6.45, 7.05, 7.55, HALF]
    wing_sections = []
    for xs in xs_list:
        t = xs / HALF
        chord = ROOT_CHORD - (ROOT_CHORD - TIP_CHORD) * (t ** 1.25)
        yle = WING_LE - SWEEP * xs
        zoff = -0.18 + 0.485 * t                       # 3.5 deg dihedral
        th = 0.14 - 0.030 * t
        wing_sections.append(_ring(xs, chord, yle, zoff, th, camber=0.02, n=N_WING))
    wing = _surface("Wing", wing_sections, mirror=True)

    # -------------------------------------------------------------- tailplane between the booms
    txs = [0.20, 0.90, 1.70, 2.50, 3.00, 3.30, 3.45]
    tail_sections = []
    for xs in txs:
        t = xs / 3.45
        chord = 1.52 - 0.62 * t
        yle = (TAIL + 2.05) - 0.03 * xs
        zoff = 0.26 + 0.03 * t
        tail_sections.append(_ring(xs, chord, yle, zoff, 0.11 - 0.02 * t, camber=0.0, n=N_TAIL))
    tail = _surface("Tailplane", tail_sections, mirror=True)

    # -------------------------------------------------------------- twin tail booms
    boom_st = [
        (NOSE - 0.85, 0.34, 0.34, 0.00),    # engine cowl front
        (NOSE - 1.15, 0.46, 0.46, 0.00),
        (NOSE - 1.65, 0.50, 0.50, 0.00),
        (NOSE - 2.35, 0.52, 0.52, 0.00),    # engine
        (NOSE - 3.20, 0.50, 0.50, 0.00),    # over the wing
        (NOSE - 4.30, 0.46, 0.48, 0.00),
        (NOSE - 5.50, 0.40, 0.44, 0.02),
        (NOSE - 6.60, 0.34, 0.40, 0.05),
        (NOSE - 8.00, 0.28, 0.36, 0.08),
        (NOSE - 9.60, 0.22, 0.30, 0.12),
        (NOSE - 11.00, 0.16, 0.22, 0.16),
        (TAIL, 0.09, 0.14, 0.18),
    ]
    boom_l = kit.tube("BoomL", boom_st, n=N_BOOM, power=2.4)
    boom_l.location = (BOOM_X, 0.0, 0.0)
    boom_r = kit.tube("BoomR", boom_st, n=N_BOOM, power=2.4)
    boom_r.location = (-BOOM_X, 0.0, 0.0)

    # -------------------------------------------------------------- twin fins + rudders
    fin_st = [
        (0.30, 1.90, TAIL + 1.90, 0.11),
        (0.85, 1.80, TAIL + 1.80, 0.10),
        (1.30, 1.55, TAIL + 1.60, 0.095),
        (1.65, 1.20, TAIL + 1.35, 0.09),
        (1.85, 0.80, TAIL + 1.10, 0.085),
        (1.92, 0.40, TAIL + 0.90, 0.08),
    ]
    fin_l = kit.fin("Fin", fin_st, camber=0.03, n=N_FIN)
    fin_l.location = (BOOM_X, 0.0, 0.0)
    fin_r = kit.fin("FinR", fin_st, camber=0.03, n=N_FIN)
    fin_r.location = (-BOOM_X, 0.0, 0.0)

    # -------------------------------------------------------------- canopy (framed greenhouse)
    canopy = kit.canopy("Canopy", [
        (NOSE - 1.55, 0.26, 0.12, 0.42),
        (NOSE - 1.95, 0.36, 0.24, 0.48),
        (NOSE - 2.45, 0.38, 0.28, 0.50),
        (NOSE - 3.00, 0.36, 0.27, 0.50),
        (NOSE - 3.55, 0.28, 0.20, 0.48),
        (NOSE - 4.05, 0.15, 0.12, 0.44),
    ], n=N_CAN)
    frames = []
    fst = [(NOSE - 1.95, 0.36, 0.24, 0.48), (NOSE - 2.45, 0.38, 0.28, 0.50),
           (NOSE - 3.00, 0.36, 0.27, 0.50), (NOSE - 3.55, 0.28, 0.20, 0.48)]
    for i, (y, hw, hh, cz) in enumerate(fst):
        frames.append(kit.box("CanopyFrame%d" % i, (hw * 2.05, 0.045, 0.045), loc=(0.0, y, cz + hh)))
        frames.append(kit.box("CanopyFrameL%d" % i, (0.045, 0.045, hh * 1.9), loc=(hw, y, cz)))
        frames.append(kit.box("CanopyFrameR%d" % i, (0.045, 0.045, hh * 1.9), loc=(-hw, y, cz)))

    # -------------------------------------------------------------- engines, props, pilot
    # the handed secondary prop is created (and renamed) FIRST so its node names stay clean
    prop_nose_y = NOSE - 0.30 - SPINNER_R * 1.1
    prop_r = _handed_prop("Propeller2", -BOOM_X, prop_nose_y, PROP_R, SPINNER_R, 0.30, -1)
    prop_l = _handed_prop("Propeller", BOOM_X, prop_nose_y, PROP_R, SPINNER_R, 0.30, +1)
    pilot = kit.pilot(EYE)

    # -------------------------------------------------------------- P-38J chin intercoolers + boom radiators
    chin_l = kit.radiator("ChinL", BOOM_X, NOSE - 1.05, -0.52, 0.52, 0.30, 0.60, mouth=False)
    chin_r = kit.radiator("ChinR", -BOOM_X, NOSE - 1.05, -0.52, 0.52, 0.30, 0.60, mouth=False)
    rad_l = kit.radiator("BoomRadL", BOOM_X + 0.44, NOSE - 4.30, -0.10, 0.24, 0.44, 0.70,
                         mouth=False)
    rad_r = kit.radiator("BoomRadR", -BOOM_X - 0.44, NOSE - 4.30, -0.10, 0.24, 0.44, 0.70,
                         mouth=False)
    rock_l = kit.box("RocketPylonL", (0.14, 0.60, 0.22), loc=(1.15, WING_LE - 1.10, -0.42))
    rock_r = kit.box("RocketPylonR", (0.14, 0.60, 0.22), loc=(-1.15, WING_LE - 1.10, -0.42))

    # the four .50 Brownings + 20 mm cannon in the nose (barrel tips flush with the nose)
    nose_guns = [kit.box("NoseGun%d" % k, (0.075, 0.55, 0.075),
                         loc=(gx, NOSE - 0.275, gz))
                 for k, (gx, gz) in enumerate(((0.20, 0.14), (-0.20, 0.14),
                                               (0.20, -0.06), (-0.20, -0.06)))]
    cannon = kit.box("Cannon", (0.09, 0.60, 0.09), loc=(0.0, NOSE - 0.30, -0.20))

    dec = kit.markings("USAAF", 0.47, NOSE - 3.55, 0.12, 0.40,
                       wing_y=WING_LE - 0.95, wing_span_x=4.6, wing_z=-0.02, wing_r=0.50,
                       fin_x=0.06, fin_y=TAIL + 1.30, fin_z=1.10, fin_r=0.36)

    # -------------------------------------------------------------- tricycle gear to the height gate
    bpy.context.view_layer.update()
    z_top = _z_max()
    z_ground = z_top - HEIGHT
    z_pivot = -0.32
    gear_len = z_pivot - WHEEL_R - z_ground
    gl = kit.gear_leg("GearL", BOOM_X, WING_LE - 0.55, z_pivot, gear_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -BOOM_X, WING_LE - 0.55, z_pivot, gear_len, WHEEL_R)
    nose_len = z_pivot - NOSE_WHEEL_R - z_ground
    gn = kit.gear_leg("GearN", 0.0, NOSE - 2.30, z_pivot, nose_len, NOSE_WHEEL_R)

    body = kit.build_body([fus, wing, tail, boom_l, boom_r, fin_l, fin_r, canopy, prop_l, prop_r,
                           pilot, chin_l, chin_r, rad_l, rad_r, rock_l, rock_r,
                           dec, gl, gr, gn, cannon] + frames + nose_guns)

    kit.refine_all(cuts=CUTS)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (0.28, NOSE - 0.10, 0.10))
    kit.empty("MuzzleR", (-0.28, NOSE - 0.10, 0.10))

    bpy.context.view_layer.update()
    _accuracy()
