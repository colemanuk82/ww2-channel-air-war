"""North American P-51D Mustang - 1:1 airframe generated from published figures.

Published: length 9.83 m (32 ft 3 in), span 11.28 m (37 ft 0 in), height 4.17 m (13 ft 8 in,
tail down), wing area 21.83 m2 (235 sq ft), wing root chord 2.64 m (104 in), tip chord 1.27 m
(50 in), dihedral 5 deg, leading-edge sweep 3 deg 35 min, 4-blade Hamilton Standard prop
3.40 m (11 ft 2 in) dia, main gear tread 3.61 m (11 ft 10 in), main wheel 0.686 m (27 in) dia,
tail wheel 0.318 m.  Every figure with its source URL is in tools/models/data/p51.md.

Frame: origin at the CG station, nose toward +Y, up +Z, right +X  (the glTF export maps that
onto Godot's -Z forward).  Original geometry only - every station below is authored here.
"""
import math

import bpy
import kit

ID = "p51"
LEN = 9.83
SPAN = 11.28
HEIGHT = 4.17
AREA = 21.83

HALF = SPAN * 0.5
ROOT_CHORD = 2.64
TIP_CHORD = 1.27
DIHEDRAL = 5.0
SWEEP = 0.0626                       # tan(3 deg 35 min): leading-edge sweepback
WING_LE = 0.72                       # wing root leading edge, ahead of the CG (CG at 27% MAC)
NOSE = WING_LE + 2.03                # spinner tip
TAIL = NOSE - LEN                    # fuselage tail / rudder post
SPINNER_R = 0.34
PROP_R = 1.70                        # 11 ft 2 in / 2
WHEEL_R = 0.343                      # 27 in tyre
TRACK = 3.61
EYE = (0.0, -0.10, 0.86)

N_FUS = 30
N_WING = 24
N_TAIL = 18
N_FIN = 18
N_CAN = 24
N_DISC = 28
CUTS = 1

TAILPLANE_Y = TAIL + 1.62


# ------------------------------------------------------------------ local helpers

def _surface(name, sections, mirror=True):
    """Loft airfoil sections already carrying absolute (x, y, z) points; mirror the half wing."""
    verts, faces = kit.loft(sections, True, True)
    if mirror:
        off = len(verts)
        verts = verts + [(-x, y, z) for (x, y, z) in verts]
        for f in list(faces):
            faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _wing_ring(xs, chord, yle, zoff, th, camber=0.03, n=12):
    ring = kit.airfoil_ring(th, camber, n)
    return [(xs, yle - chord * fx, zoff + fz * chord) for (fx, fz) in ring]


def _z_max():
    """Highest point of everything built so far (the fin tip / canopy top), for the height gate."""
    from mathutils import Vector
    hi = -1e9
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            hi = max(hi, (ob.matrix_world @ Vector(c)).z)
    return hi


def _accuracy():
    """Per-axis bbox vs the published figures; FAIL if any headline dimension is beyond 2%."""
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
    # -------------------------------------------------------------- fuselage
    fus = kit.tube("Fuselage", [
        (NOSE - 0.62, 0.13, 0.15, 0.00),     # cowl lip
        (NOSE - 0.95, 0.33, 0.34, 0.00),     # Merlin cowling
        (NOSE - 1.35, 0.42, 0.42, 0.00),
        (NOSE - 1.85, 0.46, 0.46, 0.01),     # firewall
        (NOSE - 2.45, 0.48, 0.50, 0.03),     # windscreen base
        (NOSE - 3.05, 0.48, 0.53, 0.05),     # cockpit
        (NOSE - 3.75, 0.46, 0.53, 0.08),
        (NOSE - 4.45, 0.43, 0.52, 0.12),     # belly radiator front
        (NOSE - 5.15, 0.37, 0.46, 0.17),
        (NOSE - 5.95, 0.28, 0.37, 0.22),
        (NOSE - 6.75, 0.19, 0.28, 0.27),
        (NOSE - 7.55, 0.12, 0.19, 0.31),
        (NOSE - 8.35, 0.075, 0.13, 0.34),
        (NOSE - 9.15, 0.045, 0.08, 0.35),
        (TAIL, 0.028, 0.05, 0.35),
    ], n=N_FUS, power=2.5)

    # -------------------------------------------------------------- wing (laminar planform)
    xs_list = [0.34, 0.80, 1.40, 2.10, 2.80, 3.45, 4.05, 4.60, 5.05, 5.40, HALF]
    wing_sections = []
    for xs in xs_list:
        t = xs / HALF
        chord = ROOT_CHORD - (ROOT_CHORD - TIP_CHORD) * t
        yle = WING_LE - SWEEP * xs
        zoff = -0.20 + 0.49 * t                       # 5 deg dihedral at the tip
        th = 0.15 - 0.030 * t                         # NACA 66-215 root -> 66-212 tip
        wing_sections.append(_wing_ring(xs, chord, yle, zoff, th, camber=0.025, n=N_WING))
    wing = _surface("Wing", wing_sections, mirror=True)

    # -------------------------------------------------------------- tailplane + fin
    txs = [0.20, 0.64, 1.06, 1.42, 1.66, 1.82]
    tail_sections = []
    for xs in txs:
        t = xs / 1.82
        chord = 1.46 - 0.66 * t
        yle = TAILPLANE_Y - 0.05 * xs
        zoff = 0.18 + 0.10 * t
        tail_sections.append(_wing_ring(xs, chord, yle, zoff, 0.11 - 0.02 * t, camber=0.0, n=N_TAIL))
    tail = _surface("Tailplane", tail_sections, mirror=True)

    fin = kit.fin("Fin", [
        (0.26, 1.92, TAIL + 1.98, 0.11),
        (0.80, 1.84, TAIL + 1.86, 0.10),
        (1.30, 1.62, TAIL + 1.66, 0.095),
        (1.70, 1.30, TAIL + 1.38, 0.09),
        (2.00, 0.92, TAIL + 1.08, 0.085),
        (2.22, 0.50, TAIL + 0.80, 0.08),
    ], camber=0.03, n=N_FIN)

    # dorsal fillet ahead of the fin (a P-51D feature)
    dorsal = kit.box("DorsalFillet", (0.10, 1.30, 0.34), loc=(0.0, TAIL + 3.05, 0.34),
                     rot=(9.0, 0.0, 0.0))

    # -------------------------------------------------------------- canopy (bubble)
    canopy = kit.canopy("Canopy", [
        (NOSE - 2.20, 0.28, 0.14, 0.44),     # windscreen base
        (NOSE - 2.65, 0.36, 0.26, 0.50),
        (NOSE - 3.20, 0.38, 0.31, 0.52),     # pilot hood
        (NOSE - 3.75, 0.36, 0.30, 0.52),
        (NOSE - 4.25, 0.28, 0.22, 0.50),     # rear fairing
        (NOSE - 4.75, 0.16, 0.13, 0.45),
    ], n=N_CAN)

    # -------------------------------------------------------------- engine + prop + cockpit
    prop = kit.propeller(NOSE - SPINNER_R * 1.1, radius=PROP_R, blades=4,
                         spinner_r=SPINNER_R, blade_chord=0.34)
    pilot = kit.pilot(EYE)

    # -------------------------------------------------------------- cooling + exhaust
    belly = kit.radiator("Radiator", 0.0, NOSE - 5.05, -0.54, 0.95, 0.42, 1.35)
    oil = kit.radiator("OilCooler", 0.0, NOSE - 3.95, -0.48, 0.52, 0.24, 0.55)
    carb = kit.box("CarbScoop", (0.40, 1.00, 0.26), loc=(0.0, NOSE - 1.95, 0.50))
    ex_l = kit.exhaust_bank("ExhaustL", 0.40, NOSE - 1.55, 0.25, stacks=6, spacing=0.165)
    ex_r = kit.exhaust_bank("ExhaustR", -0.40, NOSE - 1.55, 0.25, stacks=6, spacing=0.165)

    # six .50 Brownings in the wings
    guns = [kit.box("Gun%d_%d" % (s, k), (0.09, 1.20, 0.09), loc=(s * gx, WING_LE - 0.60, -0.06))
            for s in (1, -1) for k, gx in enumerate((1.70, 2.20, 2.68))]

    dec = kit.markings("USAAF", 0.42, TAIL + 3.60, 0.26, 0.40,
                       wing_y=WING_LE - 0.85, wing_span_x=3.0, wing_z=0.05, wing_r=0.44,
                       fin_x=0.06, fin_y=TAIL + 1.20, fin_z=1.30, fin_r=0.36)

    # -------------------------------------------------------------- gear sized to the height gate
    bpy.context.view_layer.update()
    z_top = _z_max()
    z_ground = z_top - HEIGHT
    z_pivot = -0.42
    gear_len = z_pivot - WHEEL_R - z_ground
    gl = kit.gear_leg("GearL", TRACK * 0.5, WING_LE - 0.30, z_pivot, gear_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, WING_LE - 0.30, z_pivot, gear_len, WHEEL_R)
    # the tail wheel hangs on a realistic strut (this model rides the mains, gear-down)
    tw_len = max(0.35, min(0.85, (0.05 - z_ground) - 1.75 * 0.16))
    tw = kit.tailwheel("TailWheel", TAIL + 1.05, 0.05, strut=tw_len, r=0.16)

    body = kit.build_body([fus, wing, tail, fin, dorsal, canopy, prop, pilot,
                           belly, oil, carb, ex_l, ex_r, dec, gl, gr, tw] + guns)

    kit.refine_all(cuts=CUTS)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (2.35, WING_LE - 0.60, -0.06))
    kit.empty("MuzzleR", (-2.35, WING_LE - 0.60, -0.06))

    bpy.context.view_layer.update()
    _accuracy()
