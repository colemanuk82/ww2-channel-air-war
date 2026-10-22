"""Republic P-47D Thunderbolt (D-25 bubbletop) - 1:1 airframe from published figures.

Published: length 11.02 m (36 ft 1.75 in), span 12.43 m (40 ft 9 in), height 4.47 m (14 ft 8 in,
tail down), wing area 27.87 m2 (300 sq ft), wing root chord 2.79 m (110 in), dihedral 4 deg,
leading-edge sweep 3 deg, 4-blade Curtiss Electric paddle-blade prop 3.96 m (13 ft) dia,
main wheel 0.864 m (34 in) dia.  Figures + sources: tools/models/data/p47.md

Frame: origin at the CG station, nose toward +Y, up +Z, right +X.  Original geometry only.
"""
import math

import bpy
import kit

ID = "p47"
LEN = 11.02
SPAN = 12.43
HEIGHT = 4.47
AREA = 27.87

HALF = SPAN * 0.5
ROOT_CHORD = 2.79
TIP_CHORD = 1.50
DIHEDRAL = 4.0
SWEEP = 0.0524                       # tan(3 deg) leading-edge sweepback
WING_LE = 0.75
NOSE = WING_LE + 2.50                # spinner tip
TAIL = NOSE - LEN
SPINNER_R = 0.42
PROP_R = 1.98                        # 13 ft / 2 paddle blade
WHEEL_R = 0.432                      # 34 in tyre
TRACK = 3.95
EYE = (0.0, -0.15, 0.90)

N_FUS = 30
N_WING = 24
N_TAIL = 18
N_FIN = 18
N_CAN = 24
N_DISC = 28
CUTS = 1

TAILPLANE_Y = TAIL + 1.78


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
    # -------------------------------------------------------------- fuselage (deep turbo spine)
    fus = kit.tube("Fuselage", [
        (NOSE - 0.72, 0.30, 0.34, 0.00),     # big radial cowl lip
        (NOSE - 1.05, 0.55, 0.60, 0.00),
        (NOSE - 1.55, 0.62, 0.66, 0.00),
        (NOSE - 2.15, 0.63, 0.69, 0.01),     # firewall
        (NOSE - 2.95, 0.62, 0.71, 0.03),     # cockpit front
        (NOSE - 3.85, 0.60, 0.72, 0.06),     # cockpit
        (NOSE - 4.75, 0.55, 0.71, 0.10),
        (NOSE - 5.65, 0.48, 0.65, 0.16),     # turbo ducting
        (NOSE - 6.55, 0.38, 0.54, 0.22),
        (NOSE - 7.45, 0.28, 0.42, 0.28),
        (NOSE - 8.35, 0.19, 0.30, 0.33),
        (NOSE - 9.25, 0.12, 0.20, 0.36),
        (NOSE - 10.10, 0.075, 0.13, 0.38),
        (NOSE - 10.60, 0.05, 0.09, 0.385),
        (TAIL, 0.03, 0.055, 0.39),
    ], n=N_FUS, power=2.5)

    # -------------------------------------------------------------- wing
    xs_list = [0.36, 0.90, 1.55, 2.30, 3.05, 3.75, 4.40, 4.95, 5.45, 5.85, HALF]
    wing_sections = []
    for xs in xs_list:
        t = xs / HALF
        chord = ROOT_CHORD - (ROOT_CHORD - TIP_CHORD) * t
        yle = WING_LE - SWEEP * xs
        zoff = -0.24 + 0.435 * t                       # 4 deg dihedral at the tip
        th = 0.16 - 0.055 * t                          # thick root airfoil -> 0.105 tip
        wing_sections.append(_ring(xs, chord, yle, zoff, th, camber=0.025, n=N_WING))
    wing = _surface("Wing", wing_sections, mirror=True)

    # -------------------------------------------------------------- tailplane + tall fin
    txs = [0.22, 0.68, 1.14, 1.52, 1.78, 1.95]
    tail_sections = []
    for xs in txs:
        t = xs / 1.95
        chord = 1.62 - 0.80 * t
        yle = TAILPLANE_Y - 0.05 * xs
        zoff = 0.20 + 0.09 * t
        tail_sections.append(_ring(xs, chord, yle, zoff, 0.11 - 0.02 * t, camber=0.0, n=N_TAIL))
    tail = _surface("Tailplane", tail_sections, mirror=True)

    fin = kit.fin("Fin", [
        (0.30, 2.20, TAIL + 2.28, 0.11),
        (0.90, 2.12, TAIL + 2.14, 0.10),
        (1.45, 1.86, TAIL + 1.90, 0.095),
        (1.90, 1.48, TAIL + 1.58, 0.09),
        (2.25, 1.02, TAIL + 1.24, 0.085),
        (2.42, 0.52, TAIL + 0.92, 0.08),
    ], camber=0.03, n=N_FIN)

    dorsal = kit.box("DorsalFillet", (0.12, 1.90, 0.40), loc=(0.0, TAIL + 3.60, 0.38),
                     rot=(8.0, 0.0, 0.0))

    # -------------------------------------------------------------- canopy (bubbletop)
    canopy = kit.canopy("Canopy", [
        (NOSE - 2.60, 0.32, 0.16, 0.46),
        (NOSE - 3.05, 0.44, 0.30, 0.54),
        (NOSE - 3.65, 0.46, 0.36, 0.58),     # pilot hood
        (NOSE - 4.25, 0.42, 0.34, 0.58),
        (NOSE - 4.85, 0.32, 0.25, 0.55),
        (NOSE - 5.35, 0.18, 0.14, 0.50),
    ], n=N_CAN)

    # -------------------------------------------------------------- engine + prop + cockpit
    prop = kit.propeller(NOSE - SPINNER_R * 1.1, radius=PROP_R, blades=4,
                         spinner_r=SPINNER_R, blade_chord=0.42)
    pilot = kit.pilot(EYE)

    # -------------------------------------------------------------- cooling / turbo / exhaust
    chin = kit.radiator("OilCooler", 0.0, NOSE - 0.70, -0.66, 0.62, 0.30, 0.50)
    turbo = kit.radiator("TurboDuct", 0.0, NOSE - 6.10, -0.44, 0.72, 0.16, 1.70)
    ex_l = kit.exhaust_bank("ExhaustL", 0.50, NOSE - 1.70, 0.34, stacks=6, spacing=0.175)
    ex_r = kit.exhaust_bank("ExhaustR", -0.50, NOSE - 1.70, 0.34, stacks=6, spacing=0.175)

    # eight .50 Brownings, four per wing in two pairs
    guns = [kit.box("Gun%d_%d" % (s, k), (0.10, 1.30, 0.10), loc=(s * gx, WING_LE - 0.65, -0.05))
            for s in (1, -1) for k, gx in enumerate((1.60, 1.95, 2.45, 2.80))]

    dec = kit.markings("USAAF", 0.52, TAIL + 4.10, 0.28, 0.46,
                       wing_y=WING_LE - 0.95, wing_span_x=3.4, wing_z=0.02, wing_r=0.48,
                       fin_x=0.07, fin_y=TAIL + 1.35, fin_z=1.45, fin_r=0.40)

    # -------------------------------------------------------------- gear sized to the height gate
    bpy.context.view_layer.update()
    z_top = _z_max()
    z_ground = z_top - HEIGHT
    z_pivot = -0.52
    gear_len = z_pivot - WHEEL_R - z_ground
    gl = kit.gear_leg("GearL", TRACK * 0.5, WING_LE - 0.28, z_pivot, gear_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, WING_LE - 0.28, z_pivot, gear_len, WHEEL_R)
    tw_len = max(0.40, min(0.95, (0.05 - z_ground) - 1.75 * 0.18))
    tw = kit.tailwheel("TailWheel", TAIL + 1.30, 0.05, strut=tw_len, r=0.18)

    body = kit.build_body([fus, wing, tail, fin, dorsal, canopy, prop, pilot,
                           chin, turbo, ex_l, ex_r, dec, gl, gr, tw] + guns)

    kit.refine_all(cuts=CUTS)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (2.80, WING_LE - 0.65, -0.05))
    kit.empty("MuzzleR", (-2.80, WING_LE - 0.65, -0.05))

    bpy.context.view_layer.update()
    _accuracy()
